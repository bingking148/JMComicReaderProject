package app

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/bingking148/JMComicReaderProject/engine/internal/dataroot"
	"github.com/bingking148/JMComicReaderProject/engine/internal/httpapi"
	"github.com/bingking148/JMComicReaderProject/engine/internal/jm"
)

type fakeCatalog struct {
	png     []byte
	fetches int
}

func (f *fakeCatalog) Search(context.Context, string, int) (jm.SearchResult, error) {
	return jm.SearchResult{Total: 1, Items: []jm.Summary{{ID: 5, Title: "搜索结果", Author: "作者"}}}, nil
}

func (f *fakeCatalog) Album(context.Context, int64) (jm.Album, error) {
	return jm.Album{
		Summary:      jm.Summary{ID: 5, Title: "本地漫画", Author: "作者", Favorites: 9, Tags: []string{"测试"}},
		Chapters:     []jm.ChapterRef{{ID: 5, Name: "第1话", Sort: 1}},
		InlineImages: []string{"00001.png", "00002.png"},
	}, nil
}

func (f *fakeCatalog) Chapter(context.Context, int64) (jm.ChapterDetail, error) {
	return jm.ChapterDetail{ID: 5, Images: []string{"00001.png", "00002.png"}}, nil
}

func (f *fakeCatalog) ScrambleID(context.Context, int64) (int, error) {
	return jm.FallbackScramble, nil
}

func (f *fakeCatalog) FetchImage(context.Context, int64, string) ([]byte, error) {
	f.fetches++
	return f.png, nil
}

func (f *fakeCatalog) FetchCover(context.Context, int64) ([]byte, error) {
	return f.png, nil
}

func TestDownloadLibraryAndRead(t *testing.T) {
	dir := t.TempDir()
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{R: 200, A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	fake := &fakeCatalog{png: buf.Bytes()}
	application, err := OpenWith(dir, fake)
	if err != nil {
		t.Fatal(err)
	}
	handler := httpapi.New(application, "token")
	res := postJSON(t, handler, "/v1/downloads", `{"albumId":5}`, "")
	if res.Code != http.StatusUnauthorized {
		t.Fatalf("token status %d body %s", res.Code, res.Body.String())
	}
	res = postJSON(t, handler, "/v1/downloads", `{"albumId":5}`, "token")
	if res.Code != http.StatusForbidden {
		t.Fatalf("age gate status %d body %s", res.Code, res.Body.String())
	}
	settings := application.Config.Get()
	settings.AgeAccepted = true
	if _, err := application.UpdateSettings(settings); err != nil {
		t.Fatal(err)
	}
	res = postJSON(t, handler, "/v1/downloads", `{"albumId":5}`, "token")
	if res.Code != http.StatusOK {
		t.Fatalf("start %d %s", res.Code, res.Body.String())
	}

	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		items := application.ListDownloads()
		if len(items) == 1 && items[0].Status == "complete" && items[0].Done == 2 {
			break
		}
		if len(items) == 1 && items[0].Status == "error" {
			t.Fatalf("download error: %s", items[0].Error)
		}
		time.Sleep(20 * time.Millisecond)
	}
	items := application.ListDownloads()
	if len(items) != 1 || items[0].Status != "complete" || items[0].Done != 2 {
		t.Fatalf("job %+v", items)
	}
	if fake.fetches != 2 {
		t.Fatalf("fetches %d", fake.fetches)
	}

	// Resume must not download pages that already exist.
	if err := application.ResumeDownload(5); err != nil {
		t.Fatal(err)
	}
	time.Sleep(80 * time.Millisecond)
	if fake.fetches != 2 {
		t.Fatalf("resume fetched again: %d", fake.fetches)
	}

	doc, err := application.Reader(5)
	if err != nil {
		t.Fatal(err)
	}
	if len(doc.Chapters) != 1 || len(doc.Chapters[0].Pages) != 2 {
		t.Fatalf("reader %+v", doc)
	}
	if _, err := os.Stat(doc.Chapters[0].Pages[0]); err != nil {
		t.Fatal(err)
	}

	lib, err := application.ListLibrary()
	if err != nil || len(lib) != 1 || lib[0].Status != "complete" {
		t.Fatalf("library %+v %v", lib, err)
	}

	// Legacy flat folder can be rescanned.
	legacy := filepath.Join(dir, "comics", "8_旧书架")
	if err := os.MkdirAll(legacy, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(legacy, "00003.png"), buf.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	n, err := application.Rescan()
	if err != nil || n < 1 {
		t.Fatalf("rescan %d %v", n, err)
	}
	if _, err := application.Reader(8); err != nil {
		t.Fatal(err)
	}
}

func postJSON(t *testing.T, h http.Handler, path, body, token string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, path, bytes.NewBufferString(body))
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("X-Engine-Token", token)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func TestSearchRoute(t *testing.T) {
	dir := t.TempDir()
	fake := &fakeCatalog{}
	application, err := OpenWith(dir, fake)
	if err != nil {
		t.Fatal(err)
	}
	settings := application.Config.Get()
	settings.AgeAccepted = true
	_, _ = application.UpdateSettings(settings)
	h := httpapi.New(application, "tok")
	req := httptest.NewRequest(http.MethodPost, "/v1/search", bytes.NewBufferString(`{"query":"词","page":1,"sort":"latest"}`))
	req.Header.Set("X-Engine-Token", "tok")
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if rec.Code != 200 {
		t.Fatal(rec.Body.String())
	}
	var payload struct {
		Items []jm.Summary `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if len(payload.Items) != 1 || payload.Items[0].ID != 5 {
		t.Fatalf("%s", rec.Body.String())
	}
	direct := httptest.NewRequest(http.MethodPost, "/v1/search", bytes.NewBufferString(`{"query":"JM5","page":1}`))
	direct.Header.Set("X-Engine-Token", "tok")
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, direct)
	body, _ := io.ReadAll(rec.Body)
	if !bytes.Contains(body, []byte(`"direct":true`)) {
		t.Fatalf("direct search: %s", body)
	}
}

func TestRelocateMoveAndSwitch(t *testing.T) {
	root := t.TempDir()
	t.Setenv("JM_DATA_POINTER", filepath.Join(root, "data_root.txt"))
	oldDir := filepath.Join(root, "old")
	application, err := OpenWith(oldDir, &fakeCatalog{})
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(oldDir, "marker.txt"), []byte("keep"), 0o644); err != nil {
		t.Fatal(err)
	}
	moved := filepath.Join(root, "moved")
	result, err := application.Relocate(moved, "move")
	if err != nil {
		t.Fatal(err)
	}
	if !result.Moved || !result.Restart {
		t.Fatalf("%+v", result)
	}
	body, err := os.ReadFile(filepath.Join(moved, "marker.txt"))
	if err != nil || string(body) != "keep" {
		t.Fatalf("marker %q %v", body, err)
	}
	if _, err := os.Stat(oldDir); !os.IsNotExist(err) {
		t.Fatalf("old directory still present: %v", err)
	}
	pointer, ok := dataroot.Read()
	if !ok || pointer != moved {
		t.Fatalf("pointer %q %v", pointer, ok)
	}

	switched := filepath.Join(root, "switched")
	fresh, err := OpenWith(moved, &fakeCatalog{})
	if err != nil {
		t.Fatal(err)
	}
	result, err = fresh.Relocate(switched, "switch")
	if err != nil {
		t.Fatal(err)
	}
	if result.Moved || !result.Restart {
		t.Fatalf("%+v", result)
	}
	if _, err := os.Stat(filepath.Join(moved, "marker.txt")); err != nil {
		t.Fatal("switch removed the old library")
	}
	if _, err := os.Stat(switched); err != nil {
		t.Fatal(err)
	}
}
