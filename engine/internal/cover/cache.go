package cover

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/bingking148/JMComicReaderProject/engine/internal/library"
)

// Source downloads a remote cover.
type Source interface {
	FetchCover(ctx context.Context, albumID int64) ([]byte, error)
}

// Cache stores search and detail covers separately from finished downloads.
type Cache struct {
	dir    string
	source Source
	mu     sync.Mutex
	wait   map[int64]*coverWait
}

type coverWait struct {
	done chan struct{}
	path string
	err  error
}

func New(dataDir string, source Source) (*Cache, error) {
	dir := filepath.Join(dataDir, "cache", "covers")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	return &Cache{dir: dir, source: source}, nil
}

func (c *Cache) Path(id int64) string {
	return filepath.Join(c.dir, fmt.Sprintf("%d.jpg", id))
}

// File returns a readable cover path, downloading it when missing.
// Concurrent callers for the same id share one download.
func (c *Cache) File(ctx context.Context, id int64) (string, error) {
	path := c.Path(id)
	if info, err := os.Stat(path); err == nil && info.Size() > 0 {
		return path, nil
	}
	c.mu.Lock()
	if c.wait == nil {
		c.wait = map[int64]*coverWait{}
	}
	if waiter, ok := c.wait[id]; ok {
		c.mu.Unlock()
		select {
		case <-waiter.done:
			return waiter.path, waiter.err
		case <-ctx.Done():
			return "", ctx.Err()
		}
	}
	waiter := &coverWait{done: make(chan struct{})}
	c.wait[id] = waiter
	c.mu.Unlock()

	got, err := c.download(ctx, id, path)
	waiter.path, waiter.err = got, err
	close(waiter.done)
	c.mu.Lock()
	delete(c.wait, id)
	c.mu.Unlock()
	return got, err
}

func (c *Cache) download(ctx context.Context, id int64, path string) (string, error) {
	if c.source == nil {
		return "", os.ErrNotExist
	}
	raw, err := c.source.FetchCover(ctx, id)
	if err != nil {
		return "", err
	}
	tmp := path + ".part"
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return "", err
	}
	if err := os.Rename(tmp, path); err != nil {
		return "", err
	}
	return path, nil
}

// Prefetch downloads a handful of covers in the background so a list can paint
// from disk. Missing covers still wait on the network the first time.
func (c *Cache) Prefetch(ids []int64) {
	if len(ids) > 12 {
		ids = ids[:12]
	}
	go func() {
		sem := make(chan struct{}, 4)
		var wg sync.WaitGroup
		for _, id := range ids {
			if id <= 0 {
				continue
			}
			wg.Add(1)
			sem <- struct{}{}
			go func(id int64) {
				defer wg.Done()
				defer func() { <-sem }()
				ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
				defer cancel()
				_, _ = c.File(ctx, id)
			}(id)
		}
		wg.Wait()
	}()
}

func (c *Cache) Size() int64 {
	return library.DirSize(c.dir)
}

// Clear removes cached covers. Downloaded comic folders are left alone.
func (c *Cache) Clear() (int64, error) {
	before := c.Size()
	entries, err := os.ReadDir(c.dir)
	if err != nil {
		return 0, err
	}
	for _, e := range entries {
		_ = os.RemoveAll(filepath.Join(c.dir, e.Name()))
	}
	return before, nil
}
