package config

import (
	"encoding/json"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

// Settings is the on-disk equivalent of the old jm_option.yml knobs that
// the product actually exposes, plus reader preferences.
type Settings struct {
	APIDomains        []string `json:"apiDomains"`
	ImageDomains      []string `json:"imageDomains"`
	Concurrency       int      `json:"concurrency"`
	Retry             int      `json:"retry"`
	AppVersion        string   `json:"appVersion"`
	AutoUpdateDomains bool     `json:"autoUpdateDomains"`
	AgeAccepted       bool     `json:"ageAccepted"`
	ReaderMode        string   `json:"readerMode"`
	FitMode           string   `json:"fitMode"`
	RTL               bool     `json:"rtl"`
	// HTTPProxy is optional. Empty means a direct connection.
	HTTPProxy string `json:"httpProxy,omitempty"`
}

// Public is what the UI is allowed to see and edit. DataDir is read-only.
type Public struct {
	Settings
	DataDir string `json:"dataDir"`
}

var (
	DefaultAPI = []string{
		"www.cdnhjk.net",
		"www.cdngwc.cc",
		"www.cdngwc.net",
		"www.cdngwc.club",
	}
	DefaultImage = []string{
		"cdn-msp.jmapiproxy1.cc",
		"cdn-msp.jmapiproxy2.cc",
		"cdn-msp2.jmapiproxy2.cc",
		"cdn-msp3.jmapiproxy2.cc",
		"cdn-msp.jmapinodeudzn.net",
		"cdn-msp3.jmapinodeudzn.net",
	}
)

func Defaults() Settings {
	return Settings{
		APIDomains:        append([]string{}, DefaultAPI...),
		ImageDomains:      append([]string{}, DefaultImage...),
		Concurrency:       5,
		Retry:             5,
		AppVersion:        "2.1.12",
		AutoUpdateDomains: true,
		ReaderMode:        "smart",
		FitMode:           "width",
	}
}

// Store persists settings atomically.
type Store struct {
	mu   sync.Mutex
	path string
	cur  Settings
}

func Open(dataDir string) (*Store, error) {
	if err := os.MkdirAll(dataDir, 0o755); err != nil {
		return nil, err
	}
	s := &Store{path: filepath.Join(dataDir, "config.json"), cur: Defaults()}
	b, err := os.ReadFile(s.path)
	if err == nil {
		_ = json.Unmarshal(b, &s.cur)
	}
	s.cur = sanitize(s.cur)
	if err := s.persist(); err != nil {
		return nil, err
	}
	return s, nil
}

func (s *Store) Get() Settings {
	s.mu.Lock()
	defer s.mu.Unlock()
	return clone(s.cur)
}

func (s *Store) Update(fn func(*Settings)) (Settings, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	fn(&s.cur)
	s.cur = sanitize(s.cur)
	if err := s.persist(); err != nil {
		return Settings{}, err
	}
	return clone(s.cur), nil
}

func (s *Store) persist() error {
	b, err := json.MarshalIndent(s.cur, "", "  ")
	if err != nil {
		return err
	}
	tmp := s.path + ".tmp"
	if err := os.WriteFile(tmp, b, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, s.path)
}

func sanitize(in Settings) Settings {
	def := Defaults()
	if len(in.APIDomains) == 0 {
		in.APIDomains = def.APIDomains
	}
	if len(in.ImageDomains) == 0 {
		in.ImageDomains = def.ImageDomains
	}
	in.APIDomains = trimList(in.APIDomains, 20)
	in.ImageDomains = trimList(in.ImageDomains, 20)
	if in.Concurrency < 1 {
		in.Concurrency = 1
	}
	if in.Concurrency > 16 {
		in.Concurrency = 16
	}
	if in.Retry < 1 {
		in.Retry = 1
	}
	if in.Retry > 8 {
		in.Retry = 8
	}
	switch in.ReaderMode {
	case "smart", "single", "spread", "strip":
	default:
		in.ReaderMode = "smart"
	}
	switch in.FitMode {
	case "width", "contain":
	default:
		in.FitMode = "width"
	}
	if in.AppVersion == "" {
		in.AppVersion = def.AppVersion
	}
	in.HTTPProxy = NormalizeProxy(in.HTTPProxy)
	return in
}

// NormalizeProxy returns a usable http(s) proxy URL, or empty for a direct connection.
// Anything that is not an http or https URL is treated as direct so a bad value
// cannot force traffic through an unintended proxy.
func NormalizeProxy(raw string) string {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return ""
	}
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" || (u.Scheme != "http" && u.Scheme != "https") {
		return ""
	}
	return u.String()
}

func trimList(in []string, max int) []string {
	var out []string
	seen := map[string]bool{}
	for _, item := range in {
		item = stringsTrim(item)
		if item == "" || seen[item] {
			continue
		}
		seen[item] = true
		out = append(out, item)
		if len(out) >= max {
			break
		}
	}
	return out
}

func stringsTrim(s string) string {
	for len(s) > 0 && (s[0] == ' ' || s[0] == '\n' || s[0] == '\t' || s[0] == '\r') {
		s = s[1:]
	}
	for len(s) > 0 && (s[len(s)-1] == ' ' || s[len(s)-1] == '\n' || s[len(s)-1] == '\t' || s[len(s)-1] == '\r' || s[len(s)-1] == '/') {
		s = s[:len(s)-1]
	}
	return s
}

func clone(s Settings) Settings {
	out := s
	out.APIDomains = append([]string{}, s.APIDomains...)
	out.ImageDomains = append([]string{}, s.ImageDomains...)
	return out
}
