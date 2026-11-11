// Package jmengine is the gomobile entrypoint embedded in Android and iOS.
// Start binds a localhost API inside the app process. It is not a remote server.
package jmengine

import (
	"sync"

	"github.com/bingking148/JMComicReaderProject/engine/internal/app"
)

var (
	mu      sync.Mutex
	current *app.Instance
)

// Start boots the engine. A second call returns the port already in use.
func Start(dataDir string) (int32, error) {
	mu.Lock()
	defer mu.Unlock()
	if current != nil {
		return int32(current.Port), nil
	}
	inst, err := app.Open(dataDir)
	if err != nil {
		return 0, err
	}
	running, err := inst.Listen(0)
	if err != nil {
		return 0, err
	}
	current = running
	return int32(running.Port), nil
}
