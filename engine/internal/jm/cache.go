package jm

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
	"time"
)

// Catalog and detail responses are safe to reuse for a while. A first miss
// still has to cross the network; a repeat view or the next open of the same
// page should not.
const (
	searchFresh = 10 * time.Minute
	searchStale = 24 * time.Hour
	detailFresh = 6 * time.Hour
	detailStale = 7 * 24 * time.Hour
)

type cacheRecord struct {
	At   int64  `json:"at"`
	Body []byte `json:"body"`
}

type cacheFlight struct {
	done chan struct{}
	body []byte
	err  error
}

func (c *Client) SetCacheDir(dir string) {
	if dir == "" {
		return
	}
	_ = os.MkdirAll(dir, 0o755)
	c.mu.Lock()
	c.cacheDir = dir
	if c.inflight == nil {
		c.inflight = map[string]*cacheFlight{}
	}
	c.mu.Unlock()
}

func (c *Client) callCached(ctx context.Context, path string, fresh, stale time.Duration, scramble bool) ([]byte, error) {
	if c.cacheDir == "" {
		return c.call(ctx, path, scramble)
	}
	if body, kind := c.loadCache(path, fresh, stale); kind == cacheFresh {
		return body, nil
	} else if kind == cacheStale {
		c.refresh(path, scramble)
		return body, nil
	}
	body, err := c.call(ctx, path, scramble)
	if err != nil {
		if old, kind := c.loadCache(path, fresh, stale); kind == cacheExpired || kind == cacheStale {
			return old, nil
		}
		return nil, err
	}
	c.storeCache(path, body)
	return body, nil
}

const (
	cacheMiss = iota
	cacheFresh
	cacheStale
	cacheExpired
)

func (c *Client) loadCache(path string, fresh, stale time.Duration) ([]byte, int) {
	c.mu.Lock()
	dir := c.cacheDir
	c.mu.Unlock()
	if dir == "" {
		return nil, cacheMiss
	}
	b, err := os.ReadFile(filepath.Join(dir, cacheName(path)))
	if err != nil {
		return nil, cacheMiss
	}
	var rec cacheRecord
	if json.Unmarshal(b, &rec) != nil || len(rec.Body) == 0 {
		return nil, cacheMiss
	}
	age := time.Since(time.Unix(0, rec.At))
	if age < fresh {
		return rec.Body, cacheFresh
	}
	if age < stale {
		return rec.Body, cacheStale
	}
	return rec.Body, cacheExpired
}

func (c *Client) storeCache(path string, body []byte) {
	c.mu.Lock()
	dir := c.cacheDir
	c.mu.Unlock()
	if dir == "" || len(body) == 0 {
		return
	}
	rec := cacheRecord{At: time.Now().UnixNano(), Body: body}
	raw, err := json.Marshal(rec)
	if err != nil {
		return
	}
	name := filepath.Join(dir, cacheName(path))
	tmp := name + ".part"
	if os.WriteFile(tmp, raw, 0o644) != nil {
		return
	}
	_ = os.Rename(tmp, name)
}

func (c *Client) refresh(path string, scramble bool) {
	c.mu.Lock()
	if c.inflight == nil {
		c.inflight = map[string]*cacheFlight{}
	}
	if _, ok := c.inflight[path]; ok {
		c.mu.Unlock()
		return
	}
	flight := &cacheFlight{done: make(chan struct{})}
	c.inflight[path] = flight
	c.mu.Unlock()
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		body, err := c.call(ctx, path, scramble)
		if err == nil {
			c.storeCache(path, body)
		}
		flight.body, flight.err = body, err
		close(flight.done)
		c.mu.Lock()
		delete(c.inflight, path)
		c.mu.Unlock()
	}()
}

func cacheName(path string) string {
	sum := sha256.Sum256([]byte(path))
	return hex.EncodeToString(sum[:]) + ".json"
}

// lookupForTest exposes cache age classes.
func (c *Client) lookupForTest(path string, fresh, stale time.Duration) (int, []byte) {
	body, kind := c.loadCache(path, fresh, stale)
	return kind, body
}
