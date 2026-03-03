#!/usr/bin/env bash
set -euo pipefail

odin_root=$(odin root | tr -d '\r')

make -C "$odin_root/vendor/miniaudio/src"
