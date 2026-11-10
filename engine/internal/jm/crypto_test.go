package jm

import "testing"

func TestTokenMatchesMobileClient(t *testing.T) {
	token, param := Token("1700566805", "2.1.12", TokenSecret)
	if token != "cce2cb071cd0cf371a2e34fd5ad66fd6" {
		t.Fatalf("token = %s", token)
	}
	if param != "1700566805,2.1.12" {
		t.Fatalf("param = %s", param)
	}
}

func TestEncryptRoundTrip(t *testing.T) {
	plain := []byte(`{"name":"标题","id":7}`)
	enc, err := Encrypt(plain, "1700000000", DataSecret)
	if err != nil {
		t.Fatal(err)
	}
	got, err := Decrypt(enc, "1700000000", DataSecret)
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(plain) {
		t.Fatalf("got %s", got)
	}
}

func TestSegments(t *testing.T) {
	cases := []struct {
		photo int
		name  string
		want  int
	}{
		{100, "00001.webp", 0},
		{230000, "00001.webp", 10},
		{300000, "00001.webp", 16},
		{500000, "00007.jpg", 6},
	}
	for _, tc := range cases {
		if got := Segments(FallbackScramble, tc.photo, tc.name); got != tc.want {
			t.Fatalf("photo %d %s: got %d want %d", tc.photo, tc.name, got, tc.want)
		}
	}
}
