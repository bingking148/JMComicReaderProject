package jm

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestClientAlbumRoundTrip(t *testing.T) {
	plain := []byte(`{"id":7,"name":"往返","author":["测"],"likes":"3","series":[],"tags":["标签"],"images":["00001.webp"]}`)
	var srv *httptest.Server
	srv = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		parts := strings.Split(r.Header.Get("tokenparam"), ",")
		ts := parts[0]
		ver := DefaultAppVersion
		if len(parts) > 1 {
			ver = parts[1]
		}
		secret := TokenSecret
		if strings.Contains(r.URL.Path, "chapter_view_template") {
			secret = ScrambleSecret
		}
		want, _ := Token(ts, ver, secret)
		if r.Header.Get("token") != want {
			http.Error(w, "bad token", http.StatusForbidden)
			return
		}
		if r.URL.Path == "/setting" {
			http.SetCookie(w, &http.Cookie{Name: "AVS", Value: "ok", Path: "/"})
			payload := []byte(`{"version":"2.1.15","img_host":"` + srv.URL + `"}`)
			enc, _ := Encrypt(payload, ts, DataSecret)
			_ = json.NewEncoder(w).Encode(map[string]any{"code": 200, "data": enc})
			return
		}
		if _, err := r.Cookie("AVS"); err != nil {
			http.Error(w, "no cookie", http.StatusForbidden)
			return
		}
		if strings.Contains(r.URL.Path, "chapter_view_template") {
			_, _ = w.Write([]byte(`var scramble_id = 220980;`))
			return
		}
		enc, err := Encrypt(plain, ts, DataSecret)
		if err != nil {
			t.Error(err)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]any{"code": 200, "data": enc})
	}))
	defer srv.Close()

	c := NewClient([]string{srv.URL}, []string{srv.URL}, DefaultAppVersion, 2)
	album, err := c.Album(context.Background(), 7)
	if err != nil {
		t.Fatal(err)
	}
	if album.Title != "往返" || album.Favorites != 3 {
		t.Fatalf("%+v", album)
	}
	if c.Version() != "2.1.15" {
		t.Fatalf("version %s", c.Version())
	}
	sid, err := c.ScrambleID(context.Background(), 7)
	if err != nil || sid != 220980 {
		t.Fatalf("scramble %d %v", sid, err)
	}
}
