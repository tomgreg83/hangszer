extends SceneTree
## Headless check of demo.tscn: presses the computer-keyboard keys, and measures the pitch of the sound that
## actually reaches Godot's audio output (no speakers needed).
##   perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script test_demo.gd

var failed := 0
var capture := AudioEffectCapture.new()

func expect(name: String, cond: bool, detail: String = "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		failed += 1


func key_event(keycode: Key, pressed: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	e.keycode = keycode
	e.pressed = pressed
	root.push_input(e)


## Listens to the output for a moment. Returns [loudest level 0..1, pitch in Hz].
func listen() -> Array:
	await create_timer(0.25).timeout          # let the note fade in
	capture.clear_buffer()
	await create_timer(0.3).timeout
	var frames := capture.get_buffer(capture.get_frames_available())
	var peak := 0.0
	var first := -1
	var last := -1
	var cycles := -1
	for i in range(1, frames.size()):
		var before := frames[i - 1].x + frames[i - 1].y
		var now := frames[i].x + frames[i].y
		peak = maxf(peak, absf(now) / 2.0)
		if before <= 0.0 and now > 0.0:       # the wave crosses zero going up: once per cycle
			if first < 0:
				first = i
			last = i
			cycles += 1
	var hz := cycles * AudioServer.get_mix_rate() / (last - first) if cycles > 0 else 0.0
	return [peak, hz]


func _init() -> void:
	capture.buffer_length = 0.5
	AudioServer.add_bus_effect(0, capture)
	var demo: Node3D = load("res://demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	var inst: Node3D = demo.get_node("Instrument")
	var state: Node = demo.get_node("MusicState")
	var to_hz: Callable = state.get_script().note_to_hz

	expect("the scene has 10 keys", inst._players.size() == 10, str(inst._players.size()))
	expect("the instrument is linked to the music state", inst.state == state)
	expect("it starts in D dorian and says so", demo.get_node("Label").text.begins_with("D dorian"))
	var cam: Camera3D = demo.get_node("Camera3D")
	expect("the camera looks at the keys", (-cam.global_basis.z).dot(-cam.global_position.normalized()) > 0.99)

	var silence: Array = await listen()
	expect("silent before any key is pressed", silence[0] < 0.001, str(silence[0]))

	# Keyboard "A" = key 0 = D3, 146.83 Hz.
	key_event(KEY_A, true)
	expect("pressing A dips the first key", inst.get_child(0).position.y < 0.0)
	var heard: Array = await listen()
	expect("pressing A makes sound", heard[0] > 0.01, "level %.3f" % heard[0])
	expect("the sound is D3, 146.83 Hz", absf(heard[1] - to_hz.call(50)) < 1.0, "%.2f Hz" % heard[1])
	key_event(KEY_A, false)
	expect("letting go raises the key", inst.get_child(0).position.y == 0.0)
	await create_timer(0.6).timeout
	silence = await listen()
	expect("silent again after letting go", silence[0] < 0.001, str(silence[0]))

	# Keyboard "4" = lydian. Then "F" = key 3 = the raised fourth, G#3, 207.65 Hz (dorian has G, 196 Hz).
	key_event(KEY_4, true)
	key_event(KEY_4, false)
	expect("pressing 4 switches to lydian", state.mode == "lydian" and demo.get_node("Label").text.begins_with("D lydian"))
	expect("the keys followed: fourth key is now G# (56)", inst.note_for_key(3) == 56, str(inst.note_for_key(3)))
	key_event(KEY_F, true)
	heard = await listen()
	expect("the sound is G#3, 207.65 Hz", absf(heard[1] - to_hz.call(56)) < 1.0, "%.2f Hz" % heard[1])
	key_event(KEY_F, false)

	# Five keys held at once must not overload the output (above 1.0 it would distort).
	for k in [KEY_A, KEY_D, KEY_G, KEY_J, KEY_L]:
		key_event(k, true)
	heard = await listen()
	expect("five notes together stay below full level", heard[0] > 0.05 and heard[0] < 0.9, "level %.3f" % heard[0])
	for k in [KEY_A, KEY_D, KEY_G, KEY_J, KEY_L]:
		key_event(k, false)
	await create_timer(0.5).timeout

	demo.free()
	AudioServer.remove_bus_effect(0, 0)
	print("all passed" if failed == 0 else "%d FAILED" % failed)
	quit(1 if failed else 0)
