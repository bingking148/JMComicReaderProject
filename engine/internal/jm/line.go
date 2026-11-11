package jm

import (
	"context"
	"sort"
	"sync"
	"time"
)

type probeHit struct {
	index   int
	elapsed time.Duration
	ok      bool
}

// RankAPI asks every configured API host for /setting at once and returns
// them fastest-first. Hosts that do not answer inside the budget stay at the
// end. If nobody answers, the original order is kept.
func (c *Client) RankAPI(ctx context.Context) []string {
	domains := c.APIDomains()
	if len(domains) < 2 {
		return domains
	}
	hits := make([]probeHit, len(domains))
	var wg sync.WaitGroup
	wg.Add(len(domains))
	for i, origin := range domains {
		go func(i int, origin string) {
			defer wg.Done()
			start := time.Now()
			pctx, cancel := context.WithTimeout(ctx, 3500*time.Millisecond)
			defer cancel()
			_, err := c.once(pctx, origin, "/setting", c.Version(), TokenSecret, false)
			hits[i] = probeHit{index: i, elapsed: time.Since(start), ok: err == nil}
		}(i, origin)
	}
	wg.Wait()
	return orderByProbe(domains, hits)
}

// RankImages orders image hosts by how fast a TLS handshake completes.
// It does not download comic pages. Hosts that do not answer stay at the end.
func (c *Client) RankImages(ctx context.Context) []string {
	domains := c.imageOrigins()
	if len(domains) < 2 {
		return domains
	}
	hits := make([]probeHit, len(domains))
	var wg sync.WaitGroup
	wg.Add(len(domains))
	for i, origin := range domains {
		go func(i int, origin string) {
			defer wg.Done()
			start := time.Now()
			pctx, cancel := context.WithTimeout(ctx, 3*time.Second)
			defer cancel()
			err := dialTLS(pctx, origin)
			hits[i] = probeHit{index: i, elapsed: time.Since(start), ok: err == nil}
		}(i, origin)
	}
	wg.Wait()
	return orderByProbe(domains, hits)
}

func (c *Client) imageOrigins() []string {
	c.mu.Lock()
	defer c.mu.Unlock()
	return append([]string{}, c.imageDomains...)
}

func orderByProbe(domains []string, hits []probeHit) []string {
	ok := false
	for _, hit := range hits {
		if hit.ok {
			ok = true
			break
		}
	}
	if !ok {
		return append([]string{}, domains...)
	}
	sort.SliceStable(hits, func(i, j int) bool {
		if hits[i].ok != hits[j].ok {
			return hits[i].ok
		}
		if hits[i].elapsed != hits[j].elapsed {
			return hits[i].elapsed < hits[j].elapsed
		}
		return hits[i].index < hits[j].index
	})
	out := make([]string, len(hits))
	for i, hit := range hits {
		out[i] = domains[hit.index]
	}
	return out
}
