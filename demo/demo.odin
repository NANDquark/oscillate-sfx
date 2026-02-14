package demo

import au "../"
import "core:fmt"
import "core:log"
import "core:time"

SAMPLE_BYTES :: #load("./assets/48000-stereo.ogg")

audio: au.Audio

main :: proc() {
	context.logger = log.create_console_logger()
	au.init(&audio)
	sample_sound, err := au.sound_load(&audio, SAMPLE_BYTES)
	if err != nil {
		panic(fmt.tprintf("err=%v", err))
	}
	sample_sound_2, err2 := au.sound_load(&audio, SAMPLE_BYTES)
	if err2 != nil {
		panic(fmt.tprintf("err=%v", err2))
	}
	au.sound_start(&audio, sample_sound)
	time.sleep(5 * time.Second)
	au.sound_start(&audio, sample_sound_2)
	time.sleep(5 * time.Second)
	au.destroy(&audio)
}
