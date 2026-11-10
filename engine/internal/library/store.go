package library

import (
	"database/sql"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	_ "modernc.org/sqlite"
)

// Comic is one locally stored album.
type Comic struct {
	ID           int64    `json:"id"`
	Title        string   `json:"title"`
	Author       string   `json:"author"`
	Tags         []string `json:"tags,omitempty"`
	Description  string   `json:"description,omitempty"`
	Favorites    int      `json:"favorites"`
	Pages        int      `json:"pages"`
	CoverPath    string   `json:"coverPath,omitempty"`
	Dir          string   `json:"dir"`
	DownloadTime string   `json:"downloadTime,omitempty"`
	LastRead     string   `json:"lastRead,omitempty"`
	FileSize     int64    `json:"fileSize"`
	Status       string   `json:"status"`
	ChapterID    string   `json:"chapterId,omitempty"`
	Page         int      `json:"page"`
	ScrollOffset float64  `json:"scrollOffset"`
}

// Job is the persisted download record.
type Job struct {
	AlbumID int64  `json:"albumId"`
	Title   string `json:"title"`
	Status  string `json:"status"`
	Done    int    `json:"done"`
	Total   int    `json:"total"`
	Message string `json:"message"`
	Error   string `json:"error,omitempty"`
}

// Progress is the reading position inside one comic.
type Progress struct {
	ChapterID string  `json:"chapterId"`
	Page      int     `json:"page"`
	Offset    float64 `json:"offset"`
}

// Store is the local library and download index.
type Store struct {
	mu sync.Mutex
	db *sql.DB
}

func Open(dataDir string) (*Store, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", filepath.Join(dataDir, "library.db"))
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	if _, err := db.Exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;`); err != nil {
		db.Close()
		return nil, err
	}
	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate() error {
	_, err := s.db.Exec(`
CREATE TABLE IF NOT EXISTS comics (
  jm_id INTEGER PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT,
  tags TEXT,
  description TEXT,
  favorites INTEGER DEFAULT 0,
  pages INTEGER DEFAULT 0,
  cover_path TEXT,
  comic_dir TEXT,
  download_time TEXT,
  last_read_time TEXT,
  file_size INTEGER DEFAULT 0,
  status TEXT DEFAULT 'partial',
  chapter_id TEXT,
  page INTEGER DEFAULT 1,
  scroll_offset REAL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS jobs (
  jm_id INTEGER PRIMARY KEY,
  title TEXT,
  status TEXT,
  done INTEGER DEFAULT 0,
  total INTEGER DEFAULT 0,
  message TEXT,
  error TEXT,
  updated_at TEXT
);
CREATE TABLE IF NOT EXISTS search_history (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  query TEXT NOT NULL,
  created_at TEXT NOT NULL
);`)
	return err
}

func (s *Store) Has(id int64) bool {
	_, err := s.Get(id)
	return err == nil
}

func (s *Store) Get(id int64) (Comic, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	row := s.db.QueryRow(`SELECT jm_id, title, author, tags, description, favorites, pages,
		cover_path, comic_dir, download_time, last_read_time, file_size, status,
		chapter_id, page, scroll_offset FROM comics WHERE jm_id = ?`, id)
	return scanComic(row)
}

func (s *Store) List() ([]Comic, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rows, err := s.db.Query(`SELECT jm_id, title, author, tags, description, favorites, pages,
		cover_path, comic_dir, download_time, last_read_time, file_size, status,
		chapter_id, page, scroll_offset FROM comics ORDER BY download_time DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Comic
	for rows.Next() {
		c, err := scanComic(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	if out == nil {
		out = []Comic{}
	}
	return out, rows.Err()
}

func (s *Store) Upsert(c Comic) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if c.Page < 1 {
		c.Page = 1
	}
	if c.Status == "" {
		c.Status = "partial"
	}
	_, err := s.db.Exec(`INSERT INTO comics (
		jm_id, title, author, tags, description, favorites, pages, cover_path, comic_dir,
		download_time, last_read_time, file_size, status, chapter_id, page, scroll_offset
	) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
	ON CONFLICT(jm_id) DO UPDATE SET
		title=excluded.title,
		author=excluded.author,
		tags=excluded.tags,
		description=excluded.description,
		favorites=excluded.favorites,
		pages=excluded.pages,
		cover_path=excluded.cover_path,
		comic_dir=excluded.comic_dir,
		download_time=excluded.download_time,
		file_size=excluded.file_size,
		status=excluded.status`,
		c.ID, c.Title, c.Author, strings.Join(c.Tags, "\n"), c.Description, c.Favorites, c.Pages,
		c.CoverPath, c.Dir, c.DownloadTime, nullIfEmpty(c.LastRead), c.FileSize, c.Status,
		c.ChapterID, c.Page, c.ScrollOffset)
	return err
}

func (s *Store) SaveProgress(id int64, p Progress) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if p.Page < 1 {
		p.Page = 1
	}
	res, err := s.db.Exec(`UPDATE comics SET chapter_id=?, page=?, scroll_offset=?, last_read_time=? WHERE jm_id=?`,
		p.ChapterID, p.Page, p.Offset, time.Now().Format(time.RFC3339), id)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return errors.New("书架里没有这本漫画")
	}
	return nil
}

func (s *Store) Delete(id int64) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err := s.db.Exec(`DELETE FROM comics WHERE jm_id=?`, id)
	if err != nil {
		return err
	}
	_, err = s.db.Exec(`DELETE FROM jobs WHERE jm_id=?`, id)
	return err
}

func (s *Store) SaveJob(j Job) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	_, err := s.db.Exec(`INSERT INTO jobs (jm_id, title, status, done, total, message, error, updated_at)
		VALUES (?,?,?,?,?,?,?,?)
		ON CONFLICT(jm_id) DO UPDATE SET
			title=excluded.title, status=excluded.status, done=excluded.done, total=excluded.total,
			message=excluded.message, error=excluded.error, updated_at=excluded.updated_at`,
		j.AlbumID, j.Title, j.Status, j.Done, j.Total, j.Message, j.Error, time.Now().Format(time.RFC3339))
	return err
}

func (s *Store) ListJobs() ([]Job, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	rows, err := s.db.Query(`SELECT jm_id, title, status, done, total, message, error FROM jobs ORDER BY updated_at DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Job
	for rows.Next() {
		var j Job
		if err := rows.Scan(&j.AlbumID, &j.Title, &j.Status, &j.Done, &j.Total, &j.Message, &j.Error); err != nil {
			return nil, err
		}
		out = append(out, j)
	}
	if out == nil {
		out = []Job{}
	}
	return out, rows.Err()
}

func (s *Store) AddSearch(query string) error {
	query = strings.TrimSpace(query)
	if query == "" {
		return nil
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	_, _ = s.db.Exec(`DELETE FROM search_history WHERE query = ?`, query)
	_, err := s.db.Exec(`INSERT INTO search_history (query, created_at) VALUES (?, ?)`, query, time.Now().Format(time.RFC3339))
	if err != nil {
		return err
	}
	_, err = s.db.Exec(`DELETE FROM search_history WHERE id NOT IN (SELECT id FROM search_history ORDER BY id DESC LIMIT 20)`)
	return err
}

func (s *Store) RecentSearches(n int) ([]string, error) {
	if n <= 0 {
		n = 8
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	rows, err := s.db.Query(`SELECT query FROM search_history ORDER BY id DESC LIMIT ?`, n)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var q string
		if err := rows.Scan(&q); err != nil {
			return nil, err
		}
		out = append(out, q)
	}
	if out == nil {
		out = []string{}
	}
	return out, rows.Err()
}

type rower interface {
	Scan(dest ...any) error
}

func scanComic(row rower) (Comic, error) {
	var c Comic
	var tags string
	var last sql.NullString
	err := row.Scan(&c.ID, &c.Title, &c.Author, &tags, &c.Description, &c.Favorites, &c.Pages,
		&c.CoverPath, &c.Dir, &c.DownloadTime, &last, &c.FileSize, &c.Status,
		&c.ChapterID, &c.Page, &c.ScrollOffset)
	if err != nil {
		return Comic{}, err
	}
	if last.Valid {
		c.LastRead = last.String
	}
	if tags != "" {
		c.Tags = strings.Split(tags, "\n")
	}
	if c.Page < 1 {
		c.Page = 1
	}
	return c, nil
}

func nullIfEmpty(s string) any {
	if s == "" {
		return nil
	}
	return s
}

// DiskChapter is stored in info.json so chapter order survives offline.
type DiskChapter struct {
	ID   int64  `json:"id"`
	Name string `json:"name"`
	Sort int    `json:"sort"`
}

// DiskInfo is the sidecar written next to downloaded pages.
type DiskInfo struct {
	ID           int64         `json:"id"`
	Title        string        `json:"title"`
	Author       string        `json:"author"`
	Tags         []string      `json:"tags"`
	Description  string        `json:"description"`
	Favorites    int           `json:"favorites"`
	Chapters     []DiskChapter `json:"chapters"`
	DownloadTime string        `json:"downloadTime"`
}

func WriteInfo(dir string, info DiskInfo) error {
	b, err := json.MarshalIndent(info, "", "  ")
	if err != nil {
		return err
	}
	tmp := filepath.Join(dir, "info.json.tmp")
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, filepath.Join(dir, "info.json"))
}

func ReadInfo(dir string) DiskInfo {
	b, err := os.ReadFile(filepath.Join(dir, "info.json"))
	if err != nil {
		return DiskInfo{}
	}
	var raw map[string]any
	if err := json.Unmarshal(b, &raw); err != nil {
		return DiskInfo{}
	}
	info := DiskInfo{
		ID:          asInt(raw["id"]),
		Title:       asStr(raw["title"]),
		Author:      asStr(raw["author"]),
		Description: asStr(raw["description"]),
		Favorites:   int(asInt(raw["favorites"])),
	}
	if t := asStr(raw["downloadTime"]); t != "" {
		info.DownloadTime = t
	} else {
		info.DownloadTime = asStr(raw["download_time"])
	}
	switch tags := raw["tags"].(type) {
	case []any:
		for _, t := range tags {
			if s := asStr(t); s != "" {
				info.Tags = append(info.Tags, s)
			}
		}
	case string:
		if tags != "" {
			info.Tags = strings.Split(tags, ",")
		}
	}
	if list, ok := raw["chapters"].([]any); ok {
		for _, item := range list {
			m, _ := item.(map[string]any)
			if m == nil {
				continue
			}
			info.Chapters = append(info.Chapters, DiskChapter{
				ID:   asInt(m["id"]),
				Name: asStr(m["name"]),
				Sort: int(asInt(m["sort"])),
			})
		}
	}
	return info
}

func asStr(v any) string {
	s, _ := v.(string)
	return s
}

func asInt(v any) int64 {
	switch t := v.(type) {
	case float64:
		return int64(t)
	case string:
		n, _ := strconv.ParseInt(t, 10, 64)
		return n
	default:
		return 0
	}
}
