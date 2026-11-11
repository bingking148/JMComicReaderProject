package jm

import "testing"

func TestFilterOrder(t *testing.T) {
	if got := FilterOrder("mr", "t"); got != "mr_t" {
		t.Fatalf("daily latest = %s", got)
	}
	if got := FilterOrder("tf", "a"); got != "tf" {
		t.Fatalf("favorites = %s", got)
	}
	if got := FilterOrder("views", "week"); got != "mv_w" {
		t.Fatalf("weekly views = %s", got)
	}
	if got := NormalizeCategory("nope"); got != "0" {
		t.Fatalf("category %s", got)
	}
}
