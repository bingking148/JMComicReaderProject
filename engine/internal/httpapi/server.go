package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/bingking148/JMComicReaderProject/engine/internal/config"
	"github.com/bingking148/JMComicReaderProject/engine/internal/jm"
	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
)

// Backend is the in-process product surface the local HTTP API exposes.
type Backend interface {
	Search(ctx context.Context, query string, page int, sort string) (jm.SearchResult, error)
	Enrich(ctx context.Context, ids []int64) (map[string]jm.Summary, error)
	Album(ctx context.Context, id int64) (any, error)
	StartDownload(id int64, restart bool) (library.Job, error)
	ListDownloads() []library.Job
	PauseDownload(id int64) error
	ResumeDownload(id int64) error
	CancelDownload(id int64)
	ListLibrary() ([]library.Comic, error)
	DeleteComic(id int64) error
	Reader(id int64) (library.ReaderDoc, error)
	SaveProgress(id int64, p library.Progress) error
	Rescan() (int, error)
	RecentSearches() ([]string, error)
	Settings() config.Public
	UpdateSettings(config.Settings) (config.Public, error)
	RefreshDomains(ctx context.Context) (config.Public, error)
	CoverFile(ctx context.Context, id int64) (string, error)
	CacheStatus() (int64, error)
	ClearCache() (int64, error)
	AgeAccepted() bool
}

// New serves the engine API on a private listener. token is required on every call.
func New(b Backend, token string) http.Handler {
	s := &server{b: b, token: token}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/health", s.health)
	mux.HandleFunc("GET /v1/settings", s.getSettings)
	mux.HandleFunc("PUT /v1/settings", s.putSettings)
	mux.HandleFunc("POST /v1/settings/domains/refresh", s.refreshDomains)
	mux.HandleFunc("POST /v1/search", s.search)
	mux.HandleFunc("POST /v1/search/enrich", s.enrich)
	mux.HandleFunc("GET /v1/history/search", s.history)
	mux.HandleFunc("GET /v1/albums/{id}", s.album)
	mux.HandleFunc("POST /v1/downloads", s.startDownload)
	mux.HandleFunc("GET /v1/downloads", s.listDownloads)
	mux.HandleFunc("POST /v1/downloads/{id}/pause", s.pause)
	mux.HandleFunc("POST /v1/downloads/{id}/resume", s.resume)
	mux.HandleFunc("DELETE /v1/downloads/{id}", s.cancel)
	mux.HandleFunc("GET /v1/library", s.library)
	mux.HandleFunc("DELETE /v1/library/{id}", s.deleteComic)
	mux.HandleFunc("GET /v1/library/{id}/reader", s.reader)
	mux.HandleFunc("PUT /v1/library/{id}/progress", s.progress)
	mux.HandleFunc("POST /v1/library/rescan", s.rescan)
	mux.HandleFunc("GET /v1/covers/{id}", s.cover)
	mux.HandleFunc("GET /v1/cache", s.cache)
	mux.HandleFunc("POST /v1/cache/clear", s.clearCache)
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				writeError(w, http.StatusInternalServerError, "内部错误")
			}
		}()
		if subtleString(r.Header.Get("X-Engine-Token"), token) == false {
			writeError(w, http.StatusUnauthorized, "未授权")
			return
		}
		if !s.allowedBeforeAge(r) && !b.AgeAccepted() {
			writeError(w, http.StatusForbidden, "请先确认已年满 18 岁")
			return
		}
		mux.ServeHTTP(w, r)
	})
}

type server struct {
	b     Backend
	token string
}

func (s *server) allowedBeforeAge(r *http.Request) bool {
	if r.URL.Path == "/v1/health" || strings.HasPrefix(r.URL.Path, "/v1/settings") {
		return true
	}
	return false
}

func (s *server) health(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "version": "2.0.0", "engine": "go"})
}

func (s *server) getSettings(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, s.b.Settings())
}

func (s *server) putSettings(w http.ResponseWriter, r *http.Request) {
	var body config.Public
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "设置格式不正确")
		return
	}
	next, err := s.b.UpdateSettings(body.Settings)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, next)
}

func (s *server) refreshDomains(w http.ResponseWriter, r *http.Request) {
	ctx, cancel := context.WithTimeout(r.Context(), 20*time.Second)
	defer cancel()
	next, err := s.b.RefreshDomains(ctx)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, next)
}

func (s *server) search(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Query string `json:"query"`
		Page  int    `json:"page"`
		Sort  string `json:"sort"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "搜索参数不正确")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	res, err := s.b.Search(ctx, body.Query, body.Page, body.Sort)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, res)
}

func (s *server) enrich(w http.ResponseWriter, r *http.Request) {
	var body struct {
		IDs []int64 `json:"ids"`
	}
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "参数不正确")
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 40*time.Second)
	defer cancel()
	out, err := s.b.Enrich(ctx, body.IDs)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": out})
}

func (s *server) history(w http.ResponseWriter, _ *http.Request) {
	items, err := s.b.RecentSearches()
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *server) album(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	album, err := s.b.Album(ctx, id)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, album)
}

func (s *server) startDownload(w http.ResponseWriter, r *http.Request) {
	var body struct {
		AlbumID int64 `json:"albumId"`
		Restart bool  `json:"restart"`
	}
	if err := readJSON(r, &body); err != nil || body.AlbumID <= 0 {
		writeError(w, http.StatusBadRequest, "缺少漫画编号")
		return
	}
	job, err := s.b.StartDownload(body.AlbumID, body.Restart)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, job)
}

func (s *server) listDownloads(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]any{"items": s.b.ListDownloads()})
}

func (s *server) pause(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := s.b.PauseDownload(id); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) resume(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := s.b.ResumeDownload(id); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) cancel(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	s.b.CancelDownload(id)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) library(w http.ResponseWriter, _ *http.Request) {
	items, err := s.b.ListLibrary()
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *server) deleteComic(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	if err := s.b.DeleteComic(id); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) reader(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	doc, err := s.b.Reader(id)
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, doc)
}

func (s *server) progress(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	var body library.Progress
	if err := readJSON(r, &body); err != nil {
		writeError(w, http.StatusBadRequest, "进度格式不正确")
		return
	}
	if err := s.b.SaveProgress(id, body); err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"ok": true})
}

func (s *server) rescan(w http.ResponseWriter, _ *http.Request) {
	n, err := s.b.Rescan()
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"imported": n})
}

func (s *server) cover(w http.ResponseWriter, r *http.Request) {
	id, ok := pathID(w, r)
	if !ok {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 30*time.Second)
	defer cancel()
	path, err := s.b.CoverFile(ctx, id)
	if err != nil {
		writeError(w, http.StatusNotFound, "封面不存在")
		return
	}
	w.Header().Set("Cache-Control", "private, max-age=86400")
	http.ServeFile(w, r, path)
}

func (s *server) cache(w http.ResponseWriter, _ *http.Request) {
	size, err := s.b.CacheStatus()
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"bytes": size,
		"mb":    float64(size) / (1024 * 1024),
	})
}

func (s *server) clearCache(w http.ResponseWriter, _ *http.Request) {
	freed, err := s.b.ClearCache()
	if err != nil {
		writeErr(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"clearedBytes": freed,
		"clearedMb":    float64(freed) / (1024 * 1024),
	})
}

func pathID(w http.ResponseWriter, r *http.Request) (int64, bool) {
	id, err := strconv.ParseInt(r.PathValue("id"), 10, 64)
	if err != nil || id <= 0 {
		writeError(w, http.StatusBadRequest, "编号不正确")
		return 0, false
	}
	return id, true
}

func readJSON(r *http.Request, dest any) error {
	defer r.Body.Close()
	dec := json.NewDecoder(io.LimitReader(r.Body, 1<<20))
	dec.DisallowUnknownFields()
	return dec.Decode(dest)
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func writeError(w http.ResponseWriter, status int, msg string) {
	writeJSON(w, status, map[string]string{"error": msg})
}

func writeErr(w http.ResponseWriter, err error) {
	var se interface{ StatusCode() int }
	if errors.As(err, &se) {
		writeError(w, se.StatusCode(), err.Error())
		return
	}
	if errors.Is(err, jm.ErrNotFound) {
		writeError(w, http.StatusNotFound, err.Error())
		return
	}
	writeError(w, http.StatusBadGateway, err.Error())
}

func subtleString(got, want string) bool {
	if len(got) != len(want) || want == "" {
		return false
	}
	var v byte
	for i := 0; i < len(got); i++ {
		v |= got[i] ^ want[i]
	}
	return v == 0
}
