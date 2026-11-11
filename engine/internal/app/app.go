package app

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/bingking148/JMComicReaderProject/engine/internal/config"
	"github.com/bingking148/JMComicReaderProject/engine/internal/cover"
	"github.com/bingking148/JMComicReaderProject/engine/internal/download"
	"github.com/bingking148/JMComicReaderProject/engine/internal/httpapi"
	"github.com/bingking148/JMComicReaderProject/engine/internal/jm"
	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
	"github.com/bingking148/JMComicReaderProject/engine/internal/version"
)

// StatusError is a user-facing failure with an HTTP status.
type StatusError struct {
	Code int
	Msg  string
}

func (e *StatusError) Error() string   { return e.Msg }
func (e *StatusError) StatusCode() int { return e.Code }

// App is the composition root shared by desktop and mobile.
type App struct {
	DataDir   string
	Config    *config.Store
	Library   *library.Store
	Downloads *download.Manager
	Covers    *cover.Cache
	Catalog   download.Catalog
	client    *jm.Client
	comics    string
}

// Instance is a running localhost server.
type Instance struct {
	Port  int
	Token string
	App   *App
	srv   *http.Server
}

// Open prepares storage and services without listening.
func Open(dataDir string) (*App, error) {
	return open(dataDir, nil)
}

// OpenWith injects a catalog, used by tests.
func OpenWith(dataDir string, cat download.Catalog) (*App, error) {
	return open(dataDir, cat)
}

func open(dataDir string, cat download.Catalog) (*App, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, err
	}
	cfg, err := config.Open(dataDir)
	if err != nil {
		return nil, err
	}
	lib, err := library.Open(dataDir)
	if err != nil {
		return nil, err
	}
	settings := cfg.Get()
	var client *jm.Client
	if cat == nil {
		client = jm.NewClient(settings.APIDomains, settings.ImageDomains, settings.AppVersion, settings.Retry)
		cat = client
	} else if c, ok := cat.(*jm.Client); ok {
		client = c
	}
	covers, err := cover.New(dataDir, cat)
	if err != nil {
		return nil, err
	}
	comics := filepath.Join(dataDir, "comics")
	if err := os.MkdirAll(comics, 0o755); err != nil {
		return nil, err
	}
	a := &App{
		DataDir: dataDir,
		Config:  cfg,
		Library: lib,
		Covers:  covers,
		Catalog: cat,
		client:  client,
		comics:  comics,
	}
	a.Downloads = download.New(comics, cat, lib, func() int {
		return a.Config.Get().Concurrency
	})
	return a, nil
}

// Listen binds 127.0.0.1 and serves until the process exits.
func (a *App) Listen(port int) (*Instance, error) {
	ln, err := net.Listen("tcp", fmt.Sprintf("127.0.0.1:%d", port))
	if err != nil {
		return nil, err
	}
	token, err := newToken()
	if err != nil {
		ln.Close()
		return nil, err
	}
	if err := os.WriteFile(filepath.Join(a.DataDir, "engine.token"), []byte(token), 0o600); err != nil {
		ln.Close()
		return nil, err
	}
	srv := &http.Server{
		Handler:           httpapi.New(a, token),
		ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      120 * time.Second,
	}
	go func() { _ = srv.Serve(ln) }()
	go a.Bootstrap(context.Background())
	tcp := ln.Addr().(*net.TCPAddr)
	return &Instance{Port: tcp.Port, Token: token, App: a, srv: srv}, nil
}

// Bootstrap refreshes API domains and warms cookies. It is safe to call repeatedly.
func (a *App) Bootstrap(ctx context.Context) {
	if a.client == nil {
		return
	}
	ctx, cancel := context.WithTimeout(ctx, 25*time.Second)
	defer cancel()
	if a.Config.Get().AutoUpdateDomains {
		if domains, err := a.client.RefreshDomains(ctx); err == nil && len(domains) > 0 {
			_, _ = a.Config.Update(func(s *config.Settings) { s.APIDomains = domains })
			a.client.SetAPIDomains(domains)
		}
	}
	_ = a.client.Warmup(ctx)
	if ver := a.client.Version(); ver != "" {
		_, _ = a.Config.Update(func(s *config.Settings) { s.AppVersion = ver })
	}
}

func (a *App) AgeAccepted() bool { return a.Config.Get().AgeAccepted }

func (a *App) Settings() config.Public {
	return config.Public{Settings: a.Config.Get(), DataDir: a.DataDir}
}

func (a *App) UpdateSettings(in config.Settings) (config.Public, error) {
	next, err := a.Config.Update(func(s *config.Settings) { *s = in })
	if err != nil {
		return config.Public{}, err
	}
	if a.client != nil {
		a.client.SetAPIDomains(next.APIDomains)
		a.client.SetImageDomains(next.ImageDomains)
		a.client.SetRetry(next.Retry)
	}
	return config.Public{Settings: next, DataDir: a.DataDir}, nil
}

func (a *App) RefreshDomains(ctx context.Context) (config.Public, error) {
	if a.client == nil {
		return config.Public{}, &StatusError{Code: 400, Msg: "当前没有在线客户端"}
	}
	domains, err := a.client.RefreshDomains(ctx)
	if err != nil {
		return config.Public{}, err
	}
	next, err := a.Config.Update(func(s *config.Settings) { s.APIDomains = domains })
	if err != nil {
		return config.Public{}, err
	}
	a.client.SetAPIDomains(domains)
	return config.Public{Settings: next, DataDir: a.DataDir}, nil
}

func (a *App) Search(ctx context.Context, query string, page int, sort string) (jm.SearchResult, error) {
	query = strings.TrimSpace(query)
	if query == "" {
		return jm.SearchResult{}, &StatusError{Code: 400, Msg: "关键词不能为空"}
	}
	if page < 1 {
		page = 1
	}
	if id, ok := jm.ParseJMID(query); ok && page == 1 {
		album, err := a.Catalog.Album(ctx, id)
		if err != nil {
			return jm.SearchResult{}, err
		}
		item := album.Summary
		item.Downloaded = a.Library.Has(id)
		_ = a.Library.AddSearch(query)
		return jm.SearchResult{Query: query, Page: 1, Total: 1, Direct: true, Items: []jm.Summary{item}}, nil
	}
	res, err := a.Catalog.Search(ctx, query, page)
	if err != nil {
		return jm.SearchResult{}, err
	}
	switch sort {
	case "favorites_asc":
		sortSummaries(res.Items, true)
	case "favorites_desc":
		sortSummaries(res.Items, false)
	}
	for i := range res.Items {
		res.Items[i].Downloaded = a.Library.Has(res.Items[i].ID)
	}
	res.Query = query
	res.Page = page
	_ = a.Library.AddSearch(query)
	return res, nil
}

func (a *App) Enrich(ctx context.Context, ids []int64) (map[string]jm.Summary, error) {
	seen := map[int64]bool{}
	var list []int64
	for _, id := range ids {
		if id <= 0 || seen[id] {
			continue
		}
		seen[id] = true
		list = append(list, id)
		if len(list) >= 16 {
			break
		}
	}
	out := map[string]jm.Summary{}
	if len(list) == 0 {
		return out, nil
	}
	type result struct {
		id int64
		s  jm.Summary
		ok bool
	}
	ch := make(chan result, len(list))
	sem := make(chan struct{}, 6)
	for _, id := range list {
		sem <- struct{}{}
		go func(id int64) {
			defer func() { <-sem }()
			album, err := a.Catalog.Album(ctx, id)
			if err != nil {
				ch <- result{id: id}
				return
			}
			s := album.Summary
			s.Downloaded = a.Library.Has(id)
			ch <- result{id: id, s: s, ok: true}
		}(id)
	}
	for range list {
		r := <-ch
		if r.ok {
			out[strconv.FormatInt(r.id, 10)] = r.s
		}
	}
	return out, nil
}

func (a *App) Album(ctx context.Context, id int64) (any, error) {
	album, err := a.Catalog.Album(ctx, id)
	if err != nil {
		return nil, err
	}
	type view struct {
		jm.Album
		Downloaded bool `json:"downloaded"`
		Partial    bool `json:"partial"`
	}
	v := view{Album: album}
	if c, err := a.Library.Get(id); err == nil {
		v.Downloaded = c.Status == "complete"
		v.Partial = c.Status != "complete"
		if c.Pages > 0 {
			v.PageCount = c.Pages
		}
	}
	return v, nil
}

func (a *App) StartDownload(id int64, restart bool) (library.Job, error) {
	if !restart {
		if c, err := a.Library.Get(id); err == nil && c.Status == "complete" {
			return library.Job{}, &StatusError{Code: 409, Msg: "这本漫画已经在书架上"}
		}
	}
	title := fmt.Sprintf("JM-%d", id)
	if c, err := a.Library.Get(id); err == nil && c.Title != "" {
		title = c.Title
	}
	return a.Downloads.Start(id, title, restart), nil
}

func (a *App) ListDownloads() []library.Job { return a.Downloads.List() }

func (a *App) PauseDownload(id int64) error  { return a.Downloads.Pause(id) }
func (a *App) ResumeDownload(id int64) error { return a.Downloads.Resume(id) }
func (a *App) CancelDownload(id int64)       { a.Downloads.Cancel(id) }

func (a *App) ListLibrary() ([]library.Comic, error) {
	items, err := a.Library.List()
	if err != nil {
		return nil, err
	}
	out := make([]library.Comic, 0, len(items))
	for _, c := range items {
		if c.Dir != "" {
			if _, err := os.Stat(c.Dir); err != nil {
				continue
			}
		}
		out = append(out, c)
	}
	return out, nil
}

func (a *App) DeleteComic(id int64) error {
	a.Downloads.Cancel(id)
	if c, err := a.Library.Get(id); err == nil && c.Dir != "" {
		_ = os.RemoveAll(c.Dir)
	} else if dir, ok := library.FindComicDir(a.comics, id); ok {
		_ = os.RemoveAll(dir)
	}
	return a.Library.Delete(id)
}

func (a *App) Reader(id int64) (library.ReaderDoc, error) {
	c, err := a.Library.Get(id)
	if err != nil {
		dir, ok := library.FindComicDir(a.comics, id)
		if !ok {
			return library.ReaderDoc{}, &StatusError{Code: 404, Msg: "还没有下载这本漫画"}
		}
		c = library.Comic{ID: id, Dir: dir, Title: filepath.Base(dir), Page: 1}
	}
	info := library.ReadInfo(c.Dir)
	if info.Title != "" {
		c.Title = info.Title
	}
	chapters := library.ScanComic(c.Dir, info)
	if len(chapters) == 0 {
		return library.ReaderDoc{}, &StatusError{Code: 404, Msg: "没有可读的页面"}
	}
	settings := a.Config.Get()
	if c.Page < 1 {
		c.Page = 1
	}
	return library.ReaderDoc{
		ID: c.ID, Title: c.Title, Chapters: chapters,
		Progress: library.Progress{ChapterID: c.ChapterID, Page: c.Page, Offset: c.ScrollOffset},
		Mode:     settings.ReaderMode, Fit: settings.FitMode, RTL: settings.RTL,
	}, nil
}

func (a *App) SaveProgress(id int64, p library.Progress) error {
	if err := a.Library.SaveProgress(id, p); err != nil {
		return &StatusError{Code: 404, Msg: err.Error()}
	}
	return nil
}

func (a *App) Rescan() (int, error) {
	entries, err := os.ReadDir(a.comics)
	if err != nil {
		return 0, err
	}
	n := 0
	for _, e := range entries {
		if !e.IsDir() {
			continue
		}
		id, ok := library.ParseAlbumID(e.Name())
		if !ok {
			continue
		}
		dir := filepath.Join(a.comics, e.Name())
		info := library.ReadInfo(dir)
		if info.ID == 0 {
			info.ID = id
		}
		if info.Title == "" {
			info.Title = strings.TrimPrefix(e.Name(), strconv.FormatInt(id, 10)+"_")
		}
		chapters := library.ScanComic(dir, info)
		pages := 0
		for _, ch := range chapters {
			pages += len(ch.Pages)
		}
		if pages == 0 {
			continue
		}
		coverPath := filepath.Join(dir, "cover.jpg")
		if st, err := os.Stat(coverPath); err != nil || st.Size() == 0 {
			coverPath = ""
		}
		status := "complete"
		if existing, err := a.Library.Get(id); err == nil && existing.Status == "partial" {
			status = "partial"
		}
		when := info.DownloadTime
		if when == "" {
			when = time.Now().Format(time.RFC3339)
		}
		if err := a.Library.Upsert(library.Comic{
			ID: id, Title: info.Title, Author: info.Author, Tags: info.Tags,
			Description: info.Description, Favorites: info.Favorites, Pages: pages,
			CoverPath: coverPath, Dir: dir, DownloadTime: when,
			FileSize: library.DirSize(dir), Status: status, Page: 1,
		}); err != nil {
			return n, err
		}
		n++
	}
	return n, nil
}

func (a *App) RecentSearches() ([]string, error) { return a.Library.RecentSearches(8) }

func (a *App) CoverFile(ctx context.Context, id int64) (string, error) {
	if c, err := a.Library.Get(id); err == nil && c.CoverPath != "" {
		if st, err := os.Stat(c.CoverPath); err == nil && st.Size() > 0 {
			return c.CoverPath, nil
		}
	}
	return a.Covers.File(ctx, id)
}

func (a *App) CacheStatus() (int64, error) {
	return a.Covers.Size(), nil
}

func (a *App) ClearCache() (int64, error) {
	return a.Covers.Clear()
}

func sortSummaries(items []jm.Summary, asc bool) {
	for i := 1; i < len(items); i++ {
		j := i
		for j > 0 {
			left, right := items[j-1].Favorites, items[j].Favorites
			swap := left < right
			if asc {
				swap = left > right
			}
			if !swap {
				break
			}
			items[j-1], items[j] = items[j], items[j-1]
			j--
		}
	}
}

func newToken() (string, error) {
	buf := make([]byte, 24)
	if _, err := rand.Read(buf); err != nil {
		return "", err
	}
	return hex.EncodeToString(buf), nil
}

// Version is the product version reported by the engine.
func Version() string { return version.Current }

// ErrClosed is reserved for a future graceful shutdown.
var ErrClosed = errors.New("engine closed")
