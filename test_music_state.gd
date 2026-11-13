extends SceneTree
## Headless check of music_state.gd and of the instrument following it:
##   perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script test_music_state.gd

const NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
var failed := 0

func expect(name: String, cond: bool, detail: String = "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		failed += 1


func name_of(midi_note: int) -> String:
	return NAMES[posmod(midi_note, 12)]


func names_of(notes: Array) -> String:
	return " ".join(notes.map(name_of))


func _init() -> void:
	var MusicState: GDScript = load("res://music_state.gd")
	var state: Node = MusicState.new()
	root.add_child(state)

	# Every mode from C: the seven scale notes, printed so you can read them.
	var expected := {
		"ionian": "C D E F G A B",
		"dorian": "C D D# F G A A#",
		"phrygian": "C C# D# F G G# A#",
		"lydian": "C D E F# G A B",
		"mixolydian": "C D E F G A A#",
		"aeolian": "C D D# F G G# A#",
		"locrian": "C C# D# F F# G# A#",
	}
	state.root_note = 48
	for m in expected:
		state.mode = m
		var notes := []
		for d in 7:
			notes.append(state.note_for_degree(d))
		print("      C %s: %s" % [m, names_of(notes)])
		expect("C %s = %s" % [m, expected[m]], names_of(notes) == expected[m])

	# Degrees past the octave and below home.
	state.mode = "dorian"
	state.root_note = 50    # D dorian
	expect("degree 0 is the home note, D3", state.note_for_degree(0) == 50)
	expect("degree 7 is the home note an octave up", state.note_for_degree(7) == 62)
	expect("degree 9 is F4 (65), two scale steps above D4", state.note_for_degree(9) == 65)
	expect("degree -1 is C3 (48), the scale note just below home", state.note_for_degree(-1) == 48)
	expect("degree -7 is the home note an octave down", state.note_for_degree(-7) == 38)
	var always_in := true
	for d in range(-20, 30):
		always_in = always_in and state.is_in_scale(state.note_for_degree(d))
	expect("every degree from -20 to 29 lands inside the scale", always_in)
	expect("a note outside the scale is rejected (D# in D dorian)", not state.is_in_scale(51))
	expect("A4 is 440 Hz", is_equal_approx(MusicState.note_to_hz(69), 440.0))

	# Changing the mode or home note tells listeners, once, and only when something really changed.
	var calls := [0]
	state.changed.connect(func(): calls[0] += 1)
	state.mode = "lydian"
	state.mode = "lydian"
	state.root_note = 48
	expect("`changed` fires once per real change", calls[0] == 2, str(calls[0]))

	# An instrument linked to the state follows it; one without a link keeps its own settings.
	var script: GDScript = load("res://modal_instrument.gd")
	var linked: Node3D = Node3D.new()
	linked.set_script(script)
	linked.state = state
	var free_one: Node3D = Node3D.new()
	free_one.set_script(script)
	for inst in [linked, free_one]:
		for i in 7:
			var key := Area3D.new()
			inst.add_child(key)
		root.add_child(inst)
	await process_frame

	var linked_notes := []
	for i in 7:
		linked_notes.append(linked.note_for_key(i))
	expect("linked instrument starts in the state's C lydian", names_of(linked_notes) == "C D E F# G A B", names_of(linked_notes))
	state.mode = "phrygian"
	state.root_note = 52    # E phrygian
	linked_notes = []
	for i in 7:
		linked_notes.append(linked.note_for_key(i))
	expect("when the state changes, the keys follow: E phrygian", names_of(linked_notes) == "E F G A B C D", names_of(linked_notes))
	expect("keys were re-pitched too", is_equal_approx(linked._players[1].pitch_scale * script.SAMPLE_HZ, MusicState.note_to_hz(53)))
	expect("an instrument with no link keeps its own D dorian", free_one.note_for_key(0) == 50 and free_one.mode == "dorian")

	state.free()
	linked.free()
	free_one.free()
	print("all passed" if failed == 0 else "%d FAILED" % failed)
	quit(1 if failed else 0)
