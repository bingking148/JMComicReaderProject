package jm

import (
	"bytes"
	"crypto/md5"
	"encoding/hex"
	"fmt"
	"image"
	"image/draw"
	"image/gif"
	"image/jpeg"
	"image/png"
	"path"
	"strconv"
	"strings"

	"golang.org/x/image/webp"
)

const (
	scrambleSplitA = 268850
	scrambleSplitB = 421926
)

// Segments is the vertical strip count for a scrambled page.
// photoID is the chapter id (not the album id). fileName may include an
// extension; only the stem is hashed, matching jmcomic's img_file_name.
func Segments(scrambleID, photoID int, fileName string) int {
	if photoID < scrambleID {
		return 0
	}
	if photoID < scrambleSplitA {
		return 10
	}
	modulus := 10
	if photoID >= scrambleSplitB {
		modulus = 8
	}
	stem := strings.TrimSuffix(fileName, path.Ext(fileName))
	sum := md5.Sum([]byte(strconv.Itoa(photoID) + stem))
	hexSum := hex.EncodeToString(sum[:])
	// ord() of the last hex character, not the nibble value.
	n := int(hexSum[len(hexSum)-1]) % modulus
	return n*2 + 2
}

// Materialize turns a downloaded page into bytes that can be shown as-is.
// Unscrambled images keep their original bytes. Scrambled images are
// reassembled and stored as JPEG.
func Materialize(raw []byte, photoID, scrambleID int, fileName string) (data []byte, ext string, err error) {
	ext = strings.ToLower(path.Ext(fileName))
	if ext == "" {
		ext = sniffExt(raw)
	}
	n := Segments(scrambleID, photoID, fileName)
	if n == 0 {
		if ext == "" {
			ext = ".jpg"
		}
		return raw, ext, nil
	}
	img, err := decodeAny(raw)
	if err != nil {
		return nil, "", fmt.Errorf("解码图片: %w", err)
	}
	out := unscramble(toRGBA(img), n)
	var buf bytes.Buffer
	if err := jpeg.Encode(&buf, out, &jpeg.Options{Quality: 85}); err != nil {
		return nil, "", err
	}
	return buf.Bytes(), ".jpg", nil
}

func decodeAny(raw []byte) (image.Image, error) {
	if len(raw) >= 12 && bytes.Equal(raw[0:4], []byte("RIFF")) && bytes.Equal(raw[8:12], []byte("WEBP")) {
		return webp.Decode(bytes.NewReader(raw))
	}
	img, _, err := image.Decode(bytes.NewReader(raw))
	return img, err
}

func toRGBA(src image.Image) *image.RGBA {
	b := src.Bounds()
	dst := image.NewRGBA(image.Rect(0, 0, b.Dx(), b.Dy()))
	draw.Draw(dst, dst.Bounds(), src, b.Min, draw.Src)
	return dst
}

func unscramble(src *image.RGBA, segments int) *image.RGBA {
	w := src.Bounds().Dx()
	h := src.Bounds().Dy()
	dst := image.NewRGBA(image.Rect(0, 0, w, h))
	if segments <= 1 || h == 0 || w == 0 {
		copy(dst.Pix, src.Pix)
		return dst
	}
	over := h % segments
	rowBytes := w * 4
	for i := 0; i < segments; i++ {
		move := h / segments
		ySrc := h - move*(i+1) - over
		yDst := move * i
		if i == 0 {
			move += over
		} else {
			yDst += over
		}
		if move <= 0 || ySrc < 0 || yDst < 0 {
			continue
		}
		if ySrc+move > h {
			move = h - ySrc
		}
		if yDst+move > h {
			move = h - yDst
		}
		for row := 0; row < move; row++ {
			s := (ySrc + row) * src.Stride
			d := (yDst + row) * dst.Stride
			copy(dst.Pix[d:d+rowBytes], src.Pix[s:s+rowBytes])
		}
	}
	return dst
}

func sniffExt(raw []byte) string {
	switch {
	case len(raw) >= 3 && raw[0] == 0xFF && raw[1] == 0xD8:
		return ".jpg"
	case len(raw) >= 8 && bytes.Equal(raw[:8], []byte{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}):
		return ".png"
	case len(raw) >= 6 && bytes.HasPrefix(raw, []byte("GIF8")):
		return ".gif"
	case len(raw) >= 12 && bytes.Equal(raw[0:4], []byte("RIFF")) && bytes.Equal(raw[8:12], []byte("WEBP")):
		return ".webp"
	default:
		return ".jpg"
	}
}

// Keep the standard decoders linked.
var _ = []any{jpeg.DefaultQuality, png.Encoder{}, gif.GIF{}}
