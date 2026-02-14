# oscillate-sfx - Minimal realtime audio mixing and playback

A very simple audio wrapper around miniaudio

## Dependencies

This package currently depends on "vendor:miniaudio" which has a C dependency. It must be compiled first before odin can build. 

`make -C "$(odin root)/vendor/miniaudio/src"`
