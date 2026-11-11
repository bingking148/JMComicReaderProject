package jm

import (
	"context"
	"os"
	"testing"
	"time"
)

func TestLiveShelves(t *testing.T) {
	if os.Getenv("JM_LIVE") == "" {
		t.Skip("set JM_LIVE=1 to check the category shelves")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 40*time.Second)
	defer cancel()
	client := NewClient([]string{
		"www.cdnhjk.net",
		"www.cdngwc.cc",
		"www.cdngwc.net",
	}, []string{
		"cdn-msp.jmapiproxy1.cc",
	}, "", 3)
	latest, err := client.Browse(ctx, 1, "0", "mr", "t")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("daily latest %d / %d", len(latest.Items), latest.Total)
	if len(latest.Items) == 0 {
		t.Fatal("daily latest is empty")
	}
	liked, err := client.Browse(ctx, 1, "0", "tf", "a")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("most favorited %d / %d", len(liked.Items), liked.Total)
	if len(liked.Items) == 0 {
		t.Fatal("favorites shelf is empty")
	}
	found, err := client.SearchOrdered(ctx, "全彩", 1, "tf", "m")
	if err != nil {
		t.Fatal(err)
	}
	t.Logf("filtered search %d / %d", len(found.Items), found.Total)
	if len(found.Items) == 0 {
		t.Fatal("filtered search is empty")
	}
}

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
