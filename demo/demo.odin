package demo

import au "../"
import "core:fmt"
import "core:log"
import "core:time"

SAMPLE_BYTES :: #load("./assets/48000-stereo.ogg")

audio: au.Audio

main :: proc() {
	context.logger = log.create_console_logger()
	au.init(&audio, 10, 100)
	sample_sound, err := au.sound_load(&audio, SAMPLE_BYTES)
	if err != nil {
		panic(fmt.tprintf("err=%v", err))
	}
	sample_sound_2, err2 := au.sound_load(&audio, SAMPLE_BYTES)
	if err2 != nil {
		panic(fmt.tprintf("err=%v", err2))
	}

	au.set_listener_position(&audio, {0, 0})
	au.sound_start(&audio, sample_sound, position = {0, 0})
	time.sleep(5 * time.Second)
	au.sound_stop(&audio, sample_sound)
	time.sleep(500 * time.Millisecond)
	au.set_listener_position(&audio, {50, 0})
	au.sound_start(&audio, sample_sound_2, position = {50, -50})
	time.sleep(5 * time.Second)
	au.sound_stop(&audio, sample_sound_2)

	au.destroy(&audio)
}
