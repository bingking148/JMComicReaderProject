package jm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func TestOrderByProbeKeepsFailuresLast(t *testing.T) {
	domains := []string{"slow", "fast", "dead"}
	hits := []probeHit{
		{index: 0, elapsed: 300 * time.Millisecond, ok: true},
		{index: 1, elapsed: 20 * time.Millisecond, ok: true},
		{index: 2, elapsed: 5 * time.Millisecond, ok: false},
	}
	got := orderByProbe(domains, hits)
	if strings.Join(got, ",") != "fast,slow,dead" {
		t.Fatalf("order %v", got)
	}
	none := []probeHit{{index: 0, ok: false}, {index: 1, ok: false}, {index: 2, ok: false}}
	kept := orderByProbe(domains, none)
	if strings.Join(kept, ",") != "slow,fast,dead" {
		t.Fatalf("all-fail order %v", kept)
	}
}

func TestCachedSearchDoesNotRepeat(t *testing.T) {
	var hits atomic.Int32
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		hits.Add(1)
		ts := strings.Split(r.Header.Get("tokenparam"), ",")[0]
		plain := []byte(`{"total":1,"content":[{"id":"9","name":"缓存","author":"甲"}]}`)
		enc, err := Encrypt(plain, ts, DataSecret)
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"code": 200, "data": enc})
	}))
	defer srv.Close()

	client := NewClient([]string{srv.URL}, nil, "2.1.12", 1)
	client.mu.Lock()
	client.warm = true
	client.mu.Unlock()
	client.SetCacheDir(t.TempDir())
	ctx := context.Background()
	first, err := client.Search(ctx, "缓存", 1)
	if err != nil || len(first.Items) != 1 || first.Items[0].Title != "缓存" {
		t.Fatalf("first %+v %v", first, err)
	}
	second, err := client.Search(ctx, "缓存", 1)
	if err != nil || len(second.Items) != 1 {
		t.Fatalf("second %+v %v", second, err)
	}
	if hits.Load() != 1 {
		t.Fatalf("origin hits %d, want 1", hits.Load())
	}
}

func TestStaleCacheStillReturns(t *testing.T) {
	dir := t.TempDir()
	client := NewClient(nil, nil, "", 1)
	client.SetCacheDir(dir)
	path := "/search?q=old"
	client.storeCache(path, []byte(`{"total":1}`))
	name := filepath.Join(dir, cacheName(path))
	raw, err := os.ReadFile(name)
	if err != nil {
		t.Fatal(err)
	}
	var rec cacheRecord
	if err := json.Unmarshal(raw, &rec); err != nil {
		t.Fatal(err)
	}
	rec.At = time.Now().Add(-2 * time.Hour).UnixNano()
	rewritten, _ := json.Marshal(rec)
	if err := os.WriteFile(name, rewritten, 0o644); err != nil {
		t.Fatal(err)
	}
	kind, body := client.lookupForTest(path, searchFresh, searchStale)
	if kind != cacheStale || string(body) != `{"total":1}` {
		t.Fatalf("kind %d body %s", kind, body)
	}
}

func TestProxyURLEmptyIsDirect(t *testing.T) {
	if proxyURL("") != nil || proxyURL("socks5://127.0.0.1:1080") != nil {
		t.Fatal("non-http proxy should be ignored")
	}
	if proxyURL("http://127.0.0.1:7890") == nil {
		t.Fatal("http proxy should parse")
	}
}
