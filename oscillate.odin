package oscillate

import "base:intrinsics"
import "base:runtime"
import hm "core:container/handle_map"
import "core:log"
import "core:strings"
import ma "vendor:miniaudio"

Audio :: struct {
	allocator:                     runtime.Allocator,
	resource_manager:              ma.resource_manager,
	engine:                        ma.engine,
	ctx:                           ma.context_type,
	playback_device_infos:         []ma.device_info,
	selected_playback_device_info: ma.device_info,
	selected_playback_device:      ma.device,
	sounds:                        hm.Static_Handle_Map(MAX_SOUNDS, Sound, Sound_Handle),
}

Sound :: struct {
	handle:     hm.Handle32,
	ma_sound:   ma.sound,
	ma_decoder: ma.decoder,
}

Sound_Handle :: hm.Handle32

MAX_SOUNDS :: 512

Error :: union #shared_nil {
	enum {
		Init_Failed,
		Sound_Load_Failed,
		Max_Sounds_Reached,
	},
}

init :: proc(audio: ^Audio, sample_rate: uint = 48_000, allocator := context.allocator) -> Error {
	context.allocator = allocator
	audio^ = {}
	audio.allocator = allocator

	succeeded := false
	defer if !succeeded {
		destroy(audio)
	}

	resource_manager_config := ma.resource_manager_config_init()
	resource_manager_config.decodedFormat = .f32
	resource_manager_config.decodedChannels = 0 // default native count
	resource_manager_config.decodedSampleRate = u32(sample_rate)
	result := ma.resource_manager_init(&resource_manager_config, &audio.resource_manager)
	if result != .SUCCESS {
		log.errorf("resource manager init failed, err=%v", result)
		return .Init_Failed
	}

	result = ma.context_init(nil, 0, nil, &audio.ctx)
	if result != .SUCCESS {
		log.errorf("context init failed, err=%v", result)
		return .Init_Failed
	}

	playback_device_count: u32
	playback_device_infos: [^]ma.device_info
	result = ma.context_get_devices(
		&audio.ctx,
		&playback_device_infos,
		&playback_device_count,
		nil,
		nil,
	)
	if result != .SUCCESS {
		log.errorf("reading device info failed, err=%v", result)
		return .Init_Failed
	}
	audio.playback_device_infos = playback_device_infos[:playback_device_count]

	found_default := false
	for device_info in audio.playback_device_infos {
		if device_info.isDefault {
			found_default = true
			audio.selected_playback_device_info = device_info
		}
	}
	if !found_default {
		log.errorf("no default playback device found")
		return .Init_Failed
	}

	device_config := ma.device_config_init(.playback)
	device_config.playback.pDeviceID = &audio.selected_playback_device_info.id
	device_config.playback.format = audio.resource_manager.config.decodedFormat
	device_config.playback.channels = 0 // default native
	device_config.sampleRate = audio.resource_manager.config.decodedSampleRate
	device_config.dataCallback = data_callback
	device_config.pUserData = audio
	result = ma.device_init(&audio.ctx, &device_config, &audio.selected_playback_device)
	if result != .SUCCESS {
		log.errorf("failed to initialize device, err=%v", result)
		return .Init_Failed
	}
	log.infof("device '%s' selected", cstring(&audio.selected_playback_device_info.name[0]))

	engine_config := ma.engine_config_init()
	engine_config.pDevice = &audio.selected_playback_device
	engine_config.pResourceManager = &audio.resource_manager
	engine_config.noAutoStart = true
	result = ma.engine_init(&engine_config, &audio.engine)
	if result != .SUCCESS {
		log.errorf("failed to initialize audio engine, err=%v", result)
		return .Init_Failed
	}

	result = ma.engine_start(&audio.engine)
	if result != .SUCCESS {
		log.errorf("failed to start audio engine, err=%v", result)
		return .Init_Failed
	}

	succeeded = true

	return nil
}

destroy :: proc(audio: ^Audio) {
	context.allocator = audio.allocator

	sounds_iterator := hm.static_iterator_make(&audio.sounds)
	for {
		sound, _, ok := hm.static_iterate(&sounds_iterator)
		if !ok do break
		_sound_destroy(sound)
	}
	ma.engine_uninit(&audio.engine)
	ma.device_uninit(&audio.selected_playback_device)
	ma.context_uninit(&audio.ctx)
	ma.resource_manager_uninit(&audio.resource_manager)
}

@(private)
data_callback: ma.device_data_proc : proc "c" (
	device: ^ma.device,
	output, input: rawptr,
	frame_count: u32,
) {
	if device == nil || device.pUserData == nil do return
	audio := (^Audio)(device.pUserData)
	ma.engine_read_pcm_frames(&audio.engine, output, u64(frame_count), nil)
}

set_volume :: proc(audio: ^Audio, volume: f32) {
	result := ma.engine_set_volume(&audio.engine, volume)
	if result != .SUCCESS {
		log.warnf("failed to set volume, err=%v", result)
	}
}

sound_load :: proc {
	sound_load_from_bytes,
	sound_load_from_file,
}

sound_load_from_file :: proc(audio: ^Audio, filepath: string) -> (Sound_Handle, Error) {
	context.allocator = audio.allocator
	cfilepath := strings.clone_to_cstring(filepath)
	defer delete(cfilepath)

	handle, add_ok := hm.add(&audio.sounds, Sound{})
	if !add_ok {
		log.errorf("maximum number of sounds (%d) reached", MAX_SOUNDS)
		return {}, .Max_Sounds_Reached
	}
	new_sound := hm.get(&audio.sounds, handle)
	result := ma.sound_init_from_file(
		&audio.engine,
		cfilepath,
		{.DECODE},
		nil,
		nil,
		&new_sound.ma_sound,
	)
	if result != .SUCCESS {
		log.errorf("failed to load sound, err=%v", result)
		return {}, .Sound_Load_Failed
	}

	return handle, nil
}

sound_load_from_bytes :: proc(audio: ^Audio, bytes: []u8) -> (Sound_Handle, Error) {
	context.allocator = audio.allocator

	handle, add_ok := hm.add(&audio.sounds, Sound{})
	if !add_ok {
		log.errorf("maximum number of sounds (%d) reached", MAX_SOUNDS)
		return {}, .Max_Sounds_Reached
	}
	new_sound := hm.get(&audio.sounds, handle)

	decoder_config := ma.decoder_config_init(
		audio.resource_manager.config.decodedFormat,
		audio.resource_manager.config.decodedChannels,
		audio.resource_manager.config.decodedSampleRate,
	)
	result := ma.decoder_init_memory(
		raw_data(bytes),
		len(bytes),
		&decoder_config,
		&new_sound.ma_decoder,
	)
	if result != .SUCCESS {
		log.errorf("failed to load sound from bytes, err=%v", result)
		return {}, .Sound_Load_Failed
	}

	result = ma.sound_init_from_data_source(
		&audio.engine,
		(^ma.data_source)(&new_sound.ma_decoder),
		{.DECODE},
		nil,
		&new_sound.ma_sound,
	)
	if result != .SUCCESS {
		log.errorf("failed to initialize sound from bytes, err=%v", result)
		ma.decoder_uninit(&new_sound.ma_decoder)
		hm.remove(&audio.sounds, handle)
		return {}, .Sound_Load_Failed
	}

	return handle, nil
}

@(private)
_sound_destroy :: proc(sound: ^Sound) {
	ma.sound_uninit(&sound.ma_sound)
	ma.decoder_uninit(&sound.ma_decoder)
}

@(private)
_sound_get :: proc(audio: ^Audio, handle: Sound_Handle) -> (^Sound, bool) {
	sound, ok := hm.get(&audio.sounds, handle)
	if !ok {
		log.errorf("unable to find sound, handle was invalid, handle=%v", handle)
		return {}, false
	}
	return sound, true
}

sound_unload :: proc(audio: ^Audio, handle: Sound_Handle) {
	sound, ok := _sound_get(audio, handle)
	if !ok do return
	_sound_destroy(sound)
	hm.remove(&audio.sounds, handle)
}

sound_start :: proc(audio: ^Audio, handle: Sound_Handle, volume: f32 = 1, looping := false) {
	sound, ok := _sound_get(audio, handle)
	if !ok do return
	ma.sound_set_volume(&sound.ma_sound, volume)
	ma.sound_set_looping(&sound.ma_sound, b32(looping))

	result := ma.sound_start(&sound.ma_sound)
	if result != .SUCCESS {
		log.warnf("failed to start sound, handle=%v, err=%v", handle, result)
	}
}

sound_set_looping :: proc(audio: ^Audio, handle: Sound_Handle, looping: bool) {
	sound, ok := _sound_get(audio, handle)
	if !ok do return
	ma.sound_set_looping(&sound.ma_sound, b32(looping))
}

sound_stop :: proc(audio: ^Audio, handle: Sound_Handle) {
	sound, ok := _sound_get(audio, handle)
	if !ok do return
	result := ma.sound_stop(&sound.ma_sound)
	if result != .SUCCESS {
		log.warnf("failed to stop sound, handle=%v, err=%v", handle, result)
	}
}

sound_set_volume :: proc(audio: ^Audio, handle: Sound_Handle, volume: f32) {
	sound, ok := _sound_get(audio, handle)
	if !ok do return
	ma.sound_set_volume(&sound.ma_sound, volume)
}

sound_get_volume :: proc(audio: ^Audio, handle: Sound_Handle) -> f32 {
	sound, ok := _sound_get(audio, handle)
	if !ok do return 0
	return ma.sound_get_volume(&sound.ma_sound)
}

sound_is_playing :: proc(audio: ^Audio, handle: Sound_Handle) -> bool {
	sound, ok := _sound_get(audio, handle)
	if !ok do return false
	return bool(ma.sound_is_playing(&sound.ma_sound))
}
