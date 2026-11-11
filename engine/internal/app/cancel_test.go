package app

import (
	"bytes"
	"context"
	"image"
	"image/color"
	"image/png"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/bingking148/JMComicReaderProject/engine/internal/jm"
	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
)

type gateCatalog struct {
	mu      sync.Mutex
	png     []byte
	fetches int
}

func (g *gateCatalog) Search(context.Context, string, int) (jm.SearchResult, error) {
	return jm.SearchResult{}, nil
}

func (g *gateCatalog) SearchOrdered(context.Context, string, int, string, string) (jm.SearchResult, error) {
	return jm.SearchResult{}, nil
}

func (g *gateCatalog) Browse(context.Context, int, string, string, string) (jm.SearchResult, error) {
	return jm.SearchResult{}, nil
}

func (g *gateCatalog) Album(context.Context, int64) (jm.Album, error) {
	return jm.Album{
		Summary:      jm.Summary{ID: 7, Title: "国漫世界", Author: "作者"},
		Chapters:     []jm.ChapterRef{{ID: 7, Name: "第1话", Sort: 1}},
		InlineImages: []string{"00001.png", "00002.png"},
	}, nil
}

func (g *gateCatalog) Chapter(context.Context, int64) (jm.ChapterDetail, error) {
	return jm.ChapterDetail{ID: 7, Images: []string{"00001.png", "00002.png"}}, nil
}

func (g *gateCatalog) ScrambleID(context.Context, int64) (int, error) {
	return jm.FallbackScramble, nil
}

func (g *gateCatalog) FetchImage(ctx context.Context, _ int64, _ string) ([]byte, error) {
	g.mu.Lock()
	g.fetches++
	n := g.fetches
	g.mu.Unlock()
	if n == 2 {
		<-ctx.Done()
		return nil, ctx.Err()
	}
	return g.png, nil
}

func (g *gateCatalog) FetchCover(context.Context, int64) ([]byte, error) {
	return g.png, nil
}

func (g *gateCatalog) count() int {
	g.mu.Lock()
	defer g.mu.Unlock()
	return g.fetches
}

func TestCancelRemovesPartialFilesAndRestartsClean(t *testing.T) {
	dir := t.TempDir()
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{R: 20, A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	fake := &gateCatalog{png: buf.Bytes()}
	application, err := OpenWith(dir, fake)
	if err != nil {
		t.Fatal(err)
	}
	settings := application.Config.Get()
	settings.Concurrency = 1
	if _, err := application.UpdateSettings(settings); err != nil {
		t.Fatal(err)
	}

	application.Downloads.Start(7, "国漫世界", false)
	var page string
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		comicDir, ok := library.FindComicDir(filepath.Join(dir, "comics"), 7)
		if ok {
			candidate := filepath.Join(comicDir, "7", "00001.png")
			if info, err := os.Stat(candidate); err == nil && info.Size() > 0 {
				page = candidate
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	if page == "" {
		t.Fatal("first page was not written")
	}

	application.CancelDownload(7)
	deadline = time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		jobs := application.ListDownloads()
		_, still := library.FindComicDir(filepath.Join(dir, "comics"), 7)
		if len(jobs) == 1 && jobs[0].Status == "canceled" && jobs[0].Done == 0 && jobs[0].Total == 0 && !still {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, err := os.Stat(page); !os.IsNotExist(err) {
		t.Fatalf("canceled page still on disk: %v", err)
	}
	if _, ok := library.FindComicDir(filepath.Join(dir, "comics"), 7); ok {
		t.Fatal("comic directory survived cancel")
	}
	lib, err := application.ListLibrary()
	if err != nil {
		t.Fatal(err)
	}
	if len(lib) != 0 {
		t.Fatalf("library still has %+v", lib)
	}
	jobs := application.ListDownloads()
	if len(jobs) != 1 || jobs[0].Status != "canceled" || jobs[0].Message != "已取消" || jobs[0].Done != 0 {
		t.Fatalf("job %+v", jobs)
	}

	before := fake.count()
	if err := application.ResumeDownload(7); err != nil {
		t.Fatal(err)
	}
	deadline = time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		jobs = application.ListDownloads()
		if len(jobs) == 1 && jobs[0].Status == "complete" && jobs[0].Done == 2 {
			break
		}
		if len(jobs) == 1 && jobs[0].Status == "error" {
			t.Fatalf("resume error: %s", jobs[0].Error)
		}
		time.Sleep(10 * time.Millisecond)
	}
	jobs = application.ListDownloads()
	if len(jobs) != 1 || jobs[0].Status != "complete" || jobs[0].Done != 2 {
		t.Fatalf("after resume %+v", jobs)
	}
	if fake.count() != before+2 {
		t.Fatalf("resume fetches = %d, want %d", fake.count(), before+2)
	}
	lib, err = application.ListLibrary()
	if err != nil || len(lib) != 1 {
		t.Fatalf("library after resume %+v %v", lib, err)
	}
}

func TestPauseKeepsPartialFiles(t *testing.T) {
	dir := t.TempDir()
	img := image.NewRGBA(image.Rect(0, 0, 2, 2))
	img.Set(0, 0, color.RGBA{A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatal(err)
	}
	fake := &gateCatalog{png: buf.Bytes()}
	application, err := OpenWith(dir, fake)
	if err != nil {
		t.Fatal(err)
	}
	settings := application.Config.Get()
	settings.Concurrency = 1
	if _, err := application.UpdateSettings(settings); err != nil {
		t.Fatal(err)
	}
	application.Downloads.Start(7, "国漫世界", false)
	var page string
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		comicDir, ok := library.FindComicDir(filepath.Join(dir, "comics"), 7)
		if ok {
			candidate := filepath.Join(comicDir, "7", "00001.png")
			if info, err := os.Stat(candidate); err == nil && info.Size() > 0 {
				page = candidate
				break
			}
		}
		time.Sleep(10 * time.Millisecond)
	}
	if page == "" {
		t.Fatal("first page was not written")
	}
	if err := application.PauseDownload(7); err != nil {
		t.Fatal(err)
	}
	time.Sleep(50 * time.Millisecond)
	if _, err := os.Stat(page); err != nil {
		t.Fatal(err)
	}
	jobs := application.ListDownloads()
	if len(jobs) != 1 || jobs[0].Status != "paused" {
		t.Fatalf("job %+v", jobs)
	}
}
