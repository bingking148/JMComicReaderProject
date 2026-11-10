package jm

import (
	"crypto/aes"
	"crypto/md5"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"strings"
)

// Token is the mobile API header pair. ts is unix seconds in decimal.
// The scramble endpoint uses a different secret than the JSON API.
func Token(ts, version, secret string) (token, tokenParam string) {
	sum := md5.Sum([]byte(ts + secret))
	return hex.EncodeToString(sum[:]), ts + "," + version
}

// Decrypt reverses the mobile API payload: base64, AES-256-ECB, PKCS7.
// The key is the hex MD5 of ts+secret, used as 32 raw bytes.
func Decrypt(b64, ts, secret string) ([]byte, error) {
	compact := strings.Map(func(r rune) rune {
		switch r {
		case ' ', '\n', '\r', '\t':
			return -1
		default:
			return r
		}
	}, strings.TrimSpace(b64))
	raw, err := base64.StdEncoding.DecodeString(compact)
	if err != nil {
		raw, err = base64.RawStdEncoding.DecodeString(compact)
		if err != nil {
			return nil, err
		}
	}
	keyHex := md5.Sum([]byte(ts + secret))
	key := []byte(hex.EncodeToString(keyHex[:]))
	block, err := aes.NewCipher(key)
	if err != nil {
		return nil, err
	}
	if len(raw) == 0 || len(raw)%aes.BlockSize != 0 {
		return nil, errors.New("密文长度无效")
	}
	out := make([]byte, len(raw))
	for i := 0; i < len(raw); i += aes.BlockSize {
		block.Decrypt(out[i:i+aes.BlockSize], raw[i:i+aes.BlockSize])
	}
	return unpad(out)
}

// Encrypt is the inverse of Decrypt, used by tests and the domain-list fixture.
func Encrypt(plain []byte, ts, secret string) (string, error) {
	keyHex := md5.Sum([]byte(ts + secret))
	key := []byte(hex.EncodeToString(keyHex[:]))
	block, err := aes.NewCipher(key)
	if err != nil {
		return "", err
	}
	padded := pad(plain)
	out := make([]byte, len(padded))
	for i := 0; i < len(padded); i += aes.BlockSize {
		block.Encrypt(out[i:i+aes.BlockSize], padded[i:i+aes.BlockSize])
	}
	return base64.StdEncoding.EncodeToString(out), nil
}

func pad(b []byte) []byte {
	n := aes.BlockSize - (len(b) % aes.BlockSize)
	if n == 0 {
		n = aes.BlockSize
	}
	out := make([]byte, len(b)+n)
	copy(out, b)
	for i := len(b); i < len(out); i++ {
		out[i] = byte(n)
	}
	return out
}

func unpad(b []byte) ([]byte, error) {
	if len(b) == 0 {
		return nil, errors.New("空明文")
	}
	n := int(b[len(b)-1])
	if n == 0 || n > aes.BlockSize || n > len(b) {
		return nil, errors.New("填充无效")
	}
	for _, c := range b[len(b)-n:] {
		if int(c) != n {
			return nil, errors.New("填充无效")
		}
	}
	return b[:len(b)-n], nil
}
