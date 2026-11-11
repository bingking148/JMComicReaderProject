package jm

import "errors"

// ErrNotFound means the album or chapter does not exist.
var ErrNotFound = errors.New("没有找到这本漫画")
