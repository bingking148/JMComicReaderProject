package config

import "testing"

func TestNormalizeProxy(t *testing.T) {
	if got := NormalizeProxy("  http://127.0.0.1:7890/ "); got != "http://127.0.0.1:7890/" {
		t.Fatalf("proxy %q", got)
	}
	if got := NormalizeProxy(""); got != "" {
		t.Fatalf("empty %q", got)
	}
	if got := NormalizeProxy("not a proxy"); got != "" {
		t.Fatalf("junk %q", got)
	}
}
