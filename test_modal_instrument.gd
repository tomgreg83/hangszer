extends SceneTree
## Headless check of modal_instrument.gd (no VR, no window, no sound output needed):
##   perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script test_modal_instrument.gd

var failed := 0

func expect(name: String, cond: bool, detail: String = "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		failed += 1


func _init() -> void:
	var script: GDScript = load("res://modal_instrument.gd")
	var inst: Node3D = Node3D.new()
	inst.set_script(script)
	for i in 9:
		var key := Area3D.new()
		key.name = "Key%d" % i
		inst.add_child(key)
	root.add_child(inst)
	await process_frame           # _ready runs

	expect("one player per Area3D key", inst._players.size() == 9, str(inst._players.size()))

	# D dorian from D3 (50): D E F G A B C, then D an octave up, then E.
	var notes := []
	for i in 9:
		notes.append(inst.note_for_key(i))
	expect("D dorian keys are D3 E3 F3 G3 A3 B3 C4 D4 E4", notes == [50, 52, 53, 55, 57, 59, 60, 62, 64], str(notes))

	# Pitch: A3 (57) is 220 Hz; the generated tone is 260 Hz, so it plays at 220/260 speed.
	expect("sample is exactly 260 Hz", is_equal_approx(script.SAMPLE_HZ, 260.0), str(script.SAMPLE_HZ))
	expect("A3 plays at 220 Hz", is_equal_approx(inst._players[4].pitch_scale * script.SAMPLE_HZ, 220.0), str(inst._players[4].pitch_scale * script.SAMPLE_HZ))
	expect("an octave up doubles the pitch", is_equal_approx(inst._players[7].pitch_scale, inst._players[0].pitch_scale * 2.0))
	expect("A4 is 440 Hz", is_equal_approx(script.note_to_hz(69), 440.0) and is_equal_approx(script.note_to_hz(57), 220.0))

	# Changing the mode and key re-pitches by itself: C lydian from C3 (48): C D E F# G A B.
	inst.root_note = 48
	inst.mode = "lydian"
	var lyd := []
	for i in 7:
		lyd.append(inst.note_for_key(i))
	expect("C lydian is C D E F# G A B", lyd == [48, 50, 52, 54, 55, 57, 59], str(lyd))
	expect("keys were re-pitched", is_equal_approx(inst._players[3].pitch_scale * script.SAMPLE_HZ, script.note_to_hz(54)))
	inst.root_note = 50
	inst.mode = "dorian"

	# Recorded sounds: each key uses the nearest sample and is played faster or slower to reach its note.
	var s48: AudioStreamWAV = script.make_tone()
	var s60: AudioStreamWAV = script.make_tone()
	var zones: Dictionary[int, AudioStream] = {}
	zones[48] = s48
	zones[60] = s60
	inst.samples = zones
	expect("F3 (53) uses the sample recorded at 48, played 5 semitones up", inst._players[2].stream == s48 and is_equal_approx(inst._players[2].pitch_scale, pow(2.0, 5.0 / 12.0)), str(inst._players[2].pitch_scale))
	expect("A3 (57) uses the sample recorded at 60, played 3 semitones down", inst._players[4].stream == s60 and is_equal_approx(inst._players[4].pitch_scale, pow(2.0, -3.0 / 12.0)), str(inst._players[4].pitch_scale))
	var none: Dictionary[int, AudioStream] = {}
	inst.samples = none
	expect("with no samples it goes back to the generated tone", inst._players[4].stream == inst._tone)

	# The generated tone loops cleanly: whole cycles, right size, looping on.
	var tone: AudioStreamWAV = inst._tone
	expect("tone is a looping 16-bit mono sound of the right length", tone.loop_mode == AudioStreamWAV.LOOP_FORWARD and tone.loop_end == 4410 and tone.data.size() == 8820 and not tone.stereo)
	var first := tone.data.decode_s16(0)
	var last := tone.data.decode_s16(8820 - 2)
	expect("loop is seamless (the last sample leads smoothly into the first)", abs(last - first) < 4000, "first %d, last %d" % [first, last])

	# Presses: a fingertip in the finger group sounds the key; leaving lets go; two fingers hold until both leave.
	var heard := []
	inst.note_on.connect(func(m, k): heard.append(["on", m, k]))
	inst.note_off.connect(func(m, k): heard.append(["off", m, k]))
	var finger1 := Node3D.new(); finger1.add_to_group("finger")
	var finger2 := Node3D.new(); finger2.add_to_group("finger")
	var stranger := Node3D.new()
	inst._on_touch(stranger, 2, 1)
	expect("something not in the finger group does nothing", heard.is_empty())
	inst._on_touch(finger1, 2, 1)
	expect("a finger touching key 2 plays F3 (53)", heard == [["on", 53, 2]], str(heard))
	inst._on_touch(finger2, 2, 1)
	inst._on_touch(finger1, 2, -1)
	expect("one of two fingers leaving does not stop it", heard.size() == 1)
	inst._on_touch(finger2, 2, -1)
	expect("the last finger leaving ends it", heard == [["on", 53, 2], ["off", 53, 2]], str(heard))
	inst.press(99)
	inst.release(-1)
	expect("keys that do not exist are ignored", heard.size() == 2)

	for n in [finger1, finger2, stranger]:
		n.free()
	print("all passed" if failed == 0 else "%d FAILED" % failed)
	quit(1 if failed else 0)
