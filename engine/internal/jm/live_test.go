package jm

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestLiveFastestLine(t *testing.T) {
	if os.Getenv("JM_LIVE") == "" {
		t.Skip("set JM_LIVE=1 to probe the official API hosts")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	client := NewClient([]string{
		"www.cdnhjk.net",
		"www.cdngwc.cc",
		"www.cdngwc.net",
		"www.cdngwc.club",
	}, []string{
		"cdn-msp.jmapiproxy1.cc",
		"cdn-msp.jmapiproxy2.cc",
	}, "", 2)
	ranked := client.RankAPI(ctx)
	t.Logf("api order %v", ranked)
	if len(ranked) == 0 {
		t.Fatal("no api hosts")
	}
	images := client.RankImages(ctx)
	t.Logf("image order %v", images)
}
