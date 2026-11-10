package main

import (
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"syscall"

	"github.com/bingking148/JMComicReaderProject/engine/jmengine"
)

func main() {
	data := flag.String("data", "", "用户数据目录")
	flag.Parse()
	dir := *data
	if dir == "" {
		dir = defaultDataDir()
	}
	port, err := jmengine.Start(dir)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	token, err := os.ReadFile(filepath.Join(dir, "engine.token"))
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	fmt.Printf("READY %d %s\n", port, string(token))
	ch := make(chan os.Signal, 1)
	signal.Notify(ch, syscall.SIGINT, syscall.SIGTERM)
	<-ch
}

func defaultDataDir() string {
	if env := os.Getenv("JM_DATA"); env != "" {
		return env
	}
	home, _ := os.UserHomeDir()
	switch runtime.GOOS {
	case "windows":
		base := os.Getenv("LOCALAPPDATA")
		if base == "" {
			base = home
		}
		return filepath.Join(base, "JMComicReader")
	case "darwin":
		return filepath.Join(home, "Library", "Application Support", "JMComicReader")
	default:
		if xdg := os.Getenv("XDG_DATA_HOME"); xdg != "" {
			return filepath.Join(xdg, "JMComicReader")
		}
		return filepath.Join(home, ".local", "share", "JMComicReader")
	}
}
