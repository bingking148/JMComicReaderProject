package cover

import (
	"context"
	"fmt"
	"os"
	"path/filepath"

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
func (c *Cache) File(ctx context.Context, id int64) (string, error) {
	path := c.Path(id)
	if info, err := os.Stat(path); err == nil && info.Size() > 0 {
		return path, nil
	}
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
