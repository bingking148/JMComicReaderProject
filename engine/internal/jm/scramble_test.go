package jm

import (
	"bytes"
	"image"
	"image/color"
	"image/png"
	"testing"
)

func TestUnscrambleSwapsHalves(t *testing.T) {
	src := image.NewRGBA(image.Rect(0, 0, 2, 4))
	for y := 0; y < 2; y++ {
		for x := 0; x < 2; x++ {
			src.Set(x, y, color.RGBA{R: 255, A: 255})
		}
	}
	for y := 2; y < 4; y++ {
		for x := 0; x < 2; x++ {
			src.Set(x, y, color.RGBA{B: 255, A: 255})
		}
	}
	var buf bytes.Buffer
	if err := png.Encode(&buf, src); err != nil {
		t.Fatal(err)
	}
	// photo id below the scramble id => segments 0, original bytes preserved.
	same, ext, err := Materialize(buf.Bytes(), 10, FallbackScramble, "00001.png")
	if err != nil {
		t.Fatal(err)
	}
	if ext != ".png" || !bytes.Equal(same, buf.Bytes()) {
		t.Fatalf("expected original png, ext %s len %d", ext, len(same))
	}

	out := unscramble(src, 2)
	if _, _, b, _ := out.At(0, 0).RGBA(); b == 0 {
		t.Fatal("top row should be the original bottom half")
	}
	r, _, b, _ := out.At(0, 2).RGBA()
	if r == 0 || b != 0 {
		t.Fatalf("bottom row should be the original top half, r=%d b=%d", r, b)
	}
}

func TestParseAlbumAndSearch(t *testing.T) {
	album, err := ParseAlbum([]byte(`{
		"id": 123,
		"name": "标题",
		"author": ["作者A", "作者B"],
		"images": ["00001.webp"],
		"description": "简介",
		"likes": "1.2万",
		"series": [],
		"tags": ["全彩", "中文"],
		"works": ["作品"],
		"actors": []
	}`))
	if err != nil {
		t.Fatal(err)
	}
	if album.Author != "作者A / 作者B" || album.Favorites != 12000 || len(album.Chapters) != 1 || album.PageCount != 1 {
		t.Fatalf("%+v", album)
	}
	if album.Chapters[0].ID != 123 {
		t.Fatalf("chapter %+v", album.Chapters[0])
	}

	multi, err := ParseAlbum([]byte(`{
		"id": 9,
		"name": "多章",
		"author": "某人",
		"likes": "10",
		"series": [
			{"id": "30", "name": "下", "sort": "2"},
			{"id": "20", "name": "上", "sort": "1"},
			{"id": "31", "name": "重复", "sort": "2"}
		],
		"tags": "中文 全彩"
	}`))
	if err != nil {
		t.Fatal(err)
	}
	if len(multi.Chapters) != 2 || multi.Chapters[0].ID != 20 || multi.Chapters[1].Name != "下" {
		t.Fatalf("%+v", multi.Chapters)
	}

	search, err := ParseSearch([]byte(`{"total":"2","content":[{"id":"5","name":"甲","author":"乙","category":{"title":"同人"}}]}`))
	if err != nil {
		t.Fatal(err)
	}
	if search.Total != 2 || search.Items[0].Tags[0] != "同人" {
		t.Fatalf("%+v", search)
	}
	id, ok := ParseJMID("jm00042")
	if !ok || id != 42 {
		t.Fatalf("id %d %v", id, ok)
	}
}
