package download

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/bingking148/JMComicReaderProject/engine/internal/jm"
	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
)

// Catalog is the JM surface used by downloads and the local API.
type Catalog interface {
	Search(ctx context.Context, query string, page int) (jm.SearchResult, error)
	Album(ctx context.Context, id int64) (jm.Album, error)
	Chapter(ctx context.Context, photoID int64) (jm.ChapterDetail, error)
	ScrambleID(ctx context.Context, photoID int64) (int, error)
	FetchImage(ctx context.Context, photoID int64, name string) ([]byte, error)
	FetchCover(ctx context.Context, albumID int64) ([]byte, error)
}

// Manager runs a queue of album downloads. Image fetches inside one album
// share a worker pool; albums themselves run one at a time so progress stays readable.
type Manager struct {
	mu      sync.Mutex
	jobs    map[int64]*running
	order   []int64
	active  bool
	cat     Catalog
	lib     *library.Store
	root    string
	workers func() int
}

type running struct {
	library.Job
	cancel context.CancelFunc
	purge  bool
}

func New(root string, cat Catalog, lib *library.Store, workers func() int) *Manager {
	m := &Manager{
		jobs:    map[int64]*running{},
		cat:     cat,
		lib:     lib,
		root:    root,
		workers: workers,
	}
	if jobs, err := lib.ListJobs(); err == nil {
		for _, j := range jobs {
			if j.Status == "running" || j.Status == "queued" {
				j.Status = "paused"
				if j.Message == "" {
					j.Message = "上次未完成，可以继续"
				}
				_ = lib.SaveJob(j)
			}
			m.jobs[j.AlbumID] = &running{Job: j}
			m.order = append(m.order, j.AlbumID)
		}
	}
	return m
}

func (m *Manager) List() []library.Job {
	m.mu.Lock()
	defer m.mu.Unlock()
	out := make([]library.Job, 0, len(m.order))
	for _, id := range m.order {
		if j, ok := m.jobs[id]; ok && j.Status != "removed" {
			out = append(out, j.Job)
		}
	}
	return out
}

// Start queues an album. restart drops finished pages and downloads again.
func (m *Manager) Start(albumID int64, title string, restart bool) library.Job {
	m.mu.Lock()
	defer m.mu.Unlock()
	if j, ok := m.jobs[albumID]; ok && (j.Status == "running" || j.Status == "queued") {
		return j.Job
	}
	if restart {
		if dir, ok := library.FindComicDir(m.root, albumID); ok {
			clearPages(dir)
		}
	}
	job := library.Job{
		AlbumID: albumID,
		Title:   title,
		Status:  "queued",
		Message: "等待下载",
	}
	if title == "" {
		job.Title = fmt.Sprintf("JM-%d", albumID)
	}
	m.jobs[albumID] = &running{Job: job}
	if !contains(m.order, albumID) {
		m.order = append([]int64{albumID}, m.order...)
	}
	_ = m.lib.SaveJob(job)
	m.kick()
	return job
}

func (m *Manager) Pause(id int64) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	j, ok := m.jobs[id]
	if !ok || (j.Status != "running" && j.Status != "queued") {
		return fmt.Errorf("没有正在进行的下载")
	}
	j.Status = "paused"
	j.Message = "已暂停"
	if j.cancel != nil {
		j.cancel()
	}
	_ = m.lib.SaveJob(j.Job)
	return nil
}

func (m *Manager) Resume(id int64) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	j, ok := m.jobs[id]
	if !ok {
		return fmt.Errorf("没有这个下载任务")
	}
	if j.Status == "running" || j.Status == "queued" {
		return nil
	}
	j.Status = "queued"
	j.Error = ""
	j.Message = "等待继续"
	_ = m.lib.SaveJob(j.Job)
	m.kick()
	return nil
}

// Halt pauses every active transfer so the library directory can be moved.
func (m *Manager) Halt() {
	m.mu.Lock()
	var cancel []context.CancelFunc
	for _, job := range m.jobs {
		if job.cancel == nil {
			continue
		}
		if job.Status == "running" || job.Status == "queued" {
			job.Status = "paused"
			job.Message = "数据目录即将更换"
			cancel = append(cancel, job.cancel)
			_ = m.lib.SaveJob(job.Job)
		}
	}
	m.mu.Unlock()
	for _, fn := range cancel {
		fn()
	}
}

func (m *Manager) Cancel(id int64) {
	m.mu.Lock()
	defer m.mu.Unlock()
	j, ok := m.jobs[id]
	if !ok || j.Status == "complete" {
		return
	}
	wasRunning := j.Status == "running"
	j.Status = "canceled"
	j.Message = "已取消"
	j.Done = 0
	j.Total = 0
	j.Error = ""
	j.purge = true
	if j.cancel != nil {
		j.cancel()
	}
	_ = m.lib.SaveJob(j.Job)
	// A running worker may still be writing the page it already fetched.
	// That directory is removed when the worker exits. Everything else can
	// be deleted now, so a later resume does not treat leftover pages as done.
	if !wasRunning {
		m.cleanupLocked(j)
	}
}

func (m *Manager) kick() {
	if m.active {
		return
	}
	var next *running
	for _, id := range m.order {
		j := m.jobs[id]
		if j != nil && j.Status == "queued" {
			next = j
			break
		}
	}
	if next == nil {
		return
	}
	m.active = true
	next.Status = "running"
	next.Message = "正在准备"
	ctx, cancel := context.WithCancel(context.Background())
	next.cancel = cancel
	_ = m.lib.SaveJob(next.Job)
	go m.run(ctx, next)
}

func (m *Manager) run(ctx context.Context, job *running) {
	defer func() {
		m.mu.Lock()
		m.active = false
		job.cancel = nil
		if job.purge {
			m.cleanupLocked(job)
		}
		m.kick()
		m.mu.Unlock()
	}()

	album, err := m.cat.Album(ctx, job.AlbumID)
	if err != nil {
		m.fail(ctx, job, err)
		return
	}
	m.mu.Lock()
	job.Title = album.Title
	m.mu.Unlock()

	dir, err := library.EnsureComicDir(m.root, album.ID, album.Title)
	if err != nil {
		m.fail(ctx, job, err)
		return
	}
	_ = os.MkdirAll(dir, 0o755)
	info := library.DiskInfo{
		ID: album.ID, Title: album.Title, Author: album.Author, Tags: album.Tags,
		Description: album.Description, Favorites: album.Favorites,
		DownloadTime: time.Now().Format(time.RFC3339),
	}
	for _, ch := range album.Chapters {
		info.Chapters = append(info.Chapters, library.DiskChapter{ID: ch.ID, Name: ch.Name, Sort: ch.Sort})
	}
	_ = library.WriteInfo(dir, info)

	coverPath := filepath.Join(dir, "cover.jpg")
	if st, err := os.Stat(coverPath); err != nil || st.Size() == 0 {
		if raw, err := m.cat.FetchCover(ctx, album.ID); err == nil {
			_ = os.WriteFile(coverPath, raw, 0o644)
		}
	}
	now := time.Now().Format(time.RFC3339)
	_ = m.lib.Upsert(library.Comic{
		ID: album.ID, Title: album.Title, Author: album.Author, Tags: album.Tags,
		Description: album.Description, Favorites: album.Favorites,
		CoverPath: coverPath, Dir: dir, DownloadTime: now, Status: "partial", Page: 1,
	})

	type task struct {
		photo int64
		name  string
		index int
		dir   string
		scram int
	}
	var tasks []task
	for _, ref := range album.Chapters {
		if ctx.Err() != nil {
			m.stopped(job)
			return
		}
		images := []string{}
		if len(album.Chapters) == 1 && ref.ID == album.ID && len(album.InlineImages) > 0 {
			images = album.InlineImages
		} else {
			detail, err := m.cat.Chapter(ctx, ref.ID)
			if err != nil {
				m.fail(ctx, job, fmt.Errorf("章节 %s: %w", ref.Name, err))
				return
			}
			images = detail.Images
			if detail.Name != "" && ref.Name == "" {
				ref.Name = detail.Name
			}
		}
		scramble, _ := m.cat.ScrambleID(ctx, ref.ID)
		chapterDir := filepath.Join(dir, fmt.Sprintf("%d", ref.ID))
		if len(album.Chapters) == 1 {
			// Keep single-chapter books flat only when the images were inlined
			// and there is no separate photo id. Chapter folders stay explicit
			// so the reader can always address them.
		}
		if err := os.MkdirAll(chapterDir, 0o755); err != nil {
			m.fail(ctx, job, err)
			return
		}
		for i, name := range images {
			tasks = append(tasks, task{
				photo: ref.ID, name: name, index: i + 1, dir: chapterDir, scram: scramble,
			})
		}
		m.update(job, 0, len(tasks), fmt.Sprintf("已获取章节 %s", ref.Name))
	}
	if len(tasks) == 0 {
		m.fail(ctx, job, fmt.Errorf("没有可下载的页面"))
		return
	}

	workers := 4
	if m.workers != nil {
		if n := m.workers(); n > 0 {
			workers = n
		}
	}
	if workers > len(tasks) {
		workers = len(tasks)
	}
	pending := make([]task, 0, len(tasks))
	done := 0
	for _, t := range tasks {
		if library.PageReady(t.dir, t.index) {
			done++
			continue
		}
		pending = append(pending, t)
	}
	m.update(job, done, len(tasks), "正在下载")

	ch := make(chan task)
	var wg sync.WaitGroup
	var prog sync.Mutex
	failed := 0
	for i := 0; i < workers; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for t := range ch {
				if ctx.Err() != nil {
					continue
				}
				reqCtx, cancel := context.WithTimeout(ctx, 45*time.Second)
				raw, err := m.cat.FetchImage(reqCtx, t.photo, t.name)
				cancel()
				if err != nil {
					prog.Lock()
					failed++
					prog.Unlock()
					continue
				}
				data, ext, err := jm.Materialize(raw, int(t.photo), t.scram, t.name)
				if err != nil {
					prog.Lock()
					failed++
					prog.Unlock()
					continue
				}
				dest := filepath.Join(t.dir, fmt.Sprintf("%05d%s", t.index, ext))
				tmp := dest + ".part"
				if err := os.WriteFile(tmp, data, 0o644); err != nil {
					prog.Lock()
					failed++
					prog.Unlock()
					continue
				}
				if err := os.Rename(tmp, dest); err != nil {
					prog.Lock()
					failed++
					prog.Unlock()
					continue
				}
				prog.Lock()
				done++
				snapshotDone := done
				prog.Unlock()
				m.update(job, snapshotDone, len(tasks), fmt.Sprintf("正在下载 %d/%d", snapshotDone, len(tasks)))
			}
		}()
	}
feed:
	for _, t := range pending {
		select {
		case <-ctx.Done():
			break feed
		case ch <- t:
		}
	}
	close(ch)
	wg.Wait()

	if ctx.Err() != nil {
		m.stopped(job)
		return
	}
	pages := 0
	for _, ch := range library.ScanComic(dir, info) {
		pages += len(ch.Pages)
	}
	size := library.DirSize(dir)
	status := "complete"
	message := "下载完成"
	errText := ""
	if failed > 0 {
		status = "error"
		message = fmt.Sprintf("有 %d 页失败，可以继续", failed)
		errText = message
	}
	m.mu.Lock()
	if job.Status == "paused" || job.Status == "canceled" {
		m.mu.Unlock()
		return
	}
	job.Status = status
	job.Done = done
	job.Total = len(tasks)
	job.Message = message
	job.Error = errText
	_ = m.lib.SaveJob(job.Job)
	m.mu.Unlock()
	_ = m.lib.Upsert(library.Comic{
		ID: album.ID, Title: album.Title, Author: album.Author, Tags: album.Tags,
		Description: album.Description, Favorites: album.Favorites, Pages: pages,
		CoverPath: coverPath, Dir: dir, DownloadTime: now, FileSize: size, Status: mapStatus(status), Page: 1,
	})
}

func mapStatus(jobStatus string) string {
	if jobStatus == "complete" {
		return "complete"
	}
	return "partial"
}

func (m *Manager) update(job *running, done, total int, message string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if job.Status == "paused" || job.Status == "canceled" {
		return
	}
	job.Done = done
	job.Total = total
	job.Message = message
	job.Status = "running"
	_ = m.lib.SaveJob(job.Job)
}

func (m *Manager) fail(ctx context.Context, job *running, err error) {
	if ctx.Err() != nil {
		m.stopped(job)
		return
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	if job.Status == "paused" || job.Status == "canceled" {
		return
	}
	job.Status = "error"
	job.Error = err.Error()
	job.Message = err.Error()
	_ = m.lib.SaveJob(job.Job)
}

func (m *Manager) stopped(job *running) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if job.Status == "running" {
		job.Status = "paused"
		job.Message = "已暂停"
		_ = m.lib.SaveJob(job.Job)
	}
}

// cleanupLocked deletes pages for a canceled job. The caller holds m.mu.
func (m *Manager) cleanupLocked(job *running) {
	if dir, ok := library.FindComicDir(m.root, job.AlbumID); ok {
		_ = os.RemoveAll(dir)
	}
	_ = m.lib.ForgetComic(job.AlbumID)
	job.Done = 0
	job.Total = 0
	job.Status = "canceled"
	job.Message = "已取消"
	job.Error = ""
	job.purge = false
	_ = m.lib.SaveJob(job.Job)
}

func contains(ids []int64, id int64) bool {
	for _, v := range ids {
		if v == id {
			return true
		}
	}
	return false
}

func clearPages(dir string) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	for _, e := range entries {
		path := filepath.Join(dir, e.Name())
		if e.IsDir() {
			_ = os.RemoveAll(path)
			continue
		}
		lower := e.Name()
		if lower == "cover.jpg" || lower == "info.json" {
			continue
		}
		_ = os.Remove(path)
	}
}
