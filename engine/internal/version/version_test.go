package version

import "testing"

func TestCurrentIsV2(t *testing.T) {
	if Current != "2.0.0" {
		t.Fatalf("product version = %q, want 2.0.0", Current)
	}
}
