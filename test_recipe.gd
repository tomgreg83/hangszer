extends SceneTree
## Headless check of the sound recipe (instrument_recipe.gd), the instrument's use of it, and the sound panel:
##   perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script test_recipe.gd

var failed := 0

func expect(name: String, cond: bool, detail: String = "") -> void:
	print(("PASS  " if cond else "FAIL  ") + name + ("   " + detail if detail != "" else ""))
	if not cond:
		failed += 1


## How loud overtone h (1 = the note itself) is in a generated tone, 0..1. The tone holds whole cycles, so this is exact.
func level(wav: AudioStreamWAV, h: int) -> float:
	var n: int = wav.data.size() / 2
	var re := 0.0
	var im := 0.0
	for i in n:
		var x := wav.data.decode_s16(i * 2) / 32767.0
		var a := TAU * 26.0 * h * i / n
		re += x * cos(a)
		im += x * sin(a)
	return 2.0 * sqrt(re * re + im * im) / n


func peak(wav: AudioStreamWAV) -> float:
	var p := 0.0
	for i in wav.data.size() / 2:
		p = maxf(p, absf(wav.data.decode_s16(i * 2)) / 32767.0)
	return p


func _init() -> void:
	var Recipe: GDScript = load("res://instrument_recipe.gd")
	var Inst: GDScript = load("res://modal_instrument.gd")

	# The original tone is unchanged: same samples as the old formula.
	var original: AudioStreamWAV = Inst.make_tone()
	var same := true
	for i in Inst.SAMPLE_FRAMES:
		var phase := TAU * Inst.SAMPLE_CYCLES * i / Inst.SAMPLE_FRAMES
		var v := 0.0
		for h in range(1, 7):
			v += sin(phase * h) / (h * h)
		var want := int(clampf(v * 0.55, -1.0, 1.0) * 32767.0)
		if absi(original.data.decode_s16(i * 2) - want) > 1:
			same = false
			break
	expect("default tone is sample-for-sample the old tone", same)
	var default_recipe = Recipe.new()
	expect("default recipe makes the same tone", Inst.make_tone(default_recipe.harmonics).data == original.data)
	expect("overtone 2 is 1/4 as loud as overtone 1", absf(level(original, 2) / level(original, 1) - 0.25) < 0.01)

	# Overtone volumes shape the sound.
	var only3: AudioStreamWAV = Inst.make_tone([0.0, 0.0, 1.0, 0.0, 0.0, 0.0])
	expect("only overtone 3 on: it sounds, the others are silent", level(only3, 3) > 0.5 and level(only3, 1) < 0.01 and level(only3, 2) < 0.01)
	var all_on: AudioStreamWAV = Inst.make_tone([1.0, 1.0, 1.0, 1.0, 1.0, 1.0])
	expect("everything at full volume does not clip", peak(all_on) <= 0.91, str(peak(all_on)))
	expect("...and the overtones stay level with each other", absf(level(all_on, 1) - level(all_on, 6)) < 0.01)
	var silent: AudioStreamWAV = Inst.make_tone([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	expect("everything at zero is silent, no crash", peak(silent) == 0.0)

	# Presets, and the file.
	for preset_name in Recipe.preset_names():
		var r = Recipe.preset(preset_name)
		expect("preset %s is in range" % preset_name, r.harmonics.size() == 6 and r.harmonics.all(func(x): return x >= 0.0 and x <= 1.0))
	expect("pure has only overtone 1", Recipe.preset("pure").harmonics == [1.0, 0.0, 0.0, 0.0, 0.0, 0.0])
	expect("unknown preset name gives the original", Recipe.preset("nope").harmonics == default_recipe.harmonics)

	var custom = Recipe.new()
	custom.harmonics = [0.9, 0.1, 0.5, 0.0, 0.25, 0.75]
	custom.attack_s = 0.3
	custom.release_s = 1.5
	var back = Recipe.new()
	back.from_dict(JSON.parse_string(JSON.stringify(custom.to_dict())))
	expect("a recipe survives being written as JSON and read back", back.harmonics == custom.harmonics and back.attack_s == 0.3 and back.release_s == 1.5)
	var wild = Recipe.new()
	wild.from_dict({"harmonics": [5.0, -2.0, "x"], "attack_s": 99, "release_s": "slow"})
	expect("bad values are kept in range or ignored", wild.harmonics[0] == 1.0 and wild.harmonics[1] == 0.0 and wild.harmonics[2] == default_recipe.harmonics[2] and wild.attack_s == 1.0 and wild.release_s == default_recipe.release_s)
	var path := "user://test_recipe_file.json"
	expect("a recipe saves to a file", custom.save_file(path))
	var loaded = Recipe.load_file(path)
	expect("...and loads from it", loaded != null and loaded.harmonics == custom.harmonics and loaded.attack_s == 0.3)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	expect("a missing file gives null", Recipe.load_file(path) == null)

	# The instrument uses a recipe.
	var inst: Node3D = Node3D.new()
	inst.set_script(Inst)
	for i in 3:
		inst.add_child(Area3D.new())
	root.add_child(inst)
	await process_frame
	var pitch_before: float = inst._players[1].pitch_scale
	var tone_before: PackedByteArray = inst._players[1].stream.data
	inst.apply_recipe(custom)
	expect("attack and release come from the recipe", inst.attack_s == 0.3 and inst.release_s == 1.5)
	expect("the keys now play the new tone", inst._players[1].stream.data != tone_before and absf(level(inst._players[1].stream, 3) - 0.5 * level(inst._players[1].stream, 1) / 0.9) < 0.01)
	expect("the pitch of each key is unchanged", is_equal_approx(inst._players[1].pitch_scale, pitch_before))

	# The panel.
	var Panel: GDScript = load("res://recipe_panel.gd")
	var panel: PanelContainer = Panel.new()
	panel.instrument = inst
	panel.save_path = "user://test_panel_sound.json"
	root.add_child(panel)
	await process_frame
	expect("the panel has a slider per overtone, attack and release", panel._sliders.size() == 6 and panel._attack != null and panel._release != null)
	expect("no panel control takes the keyboard", panel._presets.focus_mode == Control.FOCUS_NONE and panel._sliders.all(func(s): return s.focus_mode == Control.FOCUS_NONE))
	panel._sliders[1].value = 0.0
	expect("moving a slider changes the instrument's tone", level(inst._players[0].stream, 2) < 0.01 and level(inst._players[0].stream, 1) > 0.3)
	panel._attack.value = 0.5
	expect("the attack slider sets the attack", inst.attack_s == 0.5)
	var pure_index: int = Recipe.preset_names().find("pure")
	panel._presets.select(pure_index)
	panel._on_preset(pure_index)
	expect("choosing a preset moves the sliders and the sound", panel._sliders[2].value == 0.0 and level(inst._players[0].stream, 3) < 0.01 and inst.attack_s == 0.05)
	panel._sliders[0].value = 0.4
	panel.save()
	panel._on_preset(Recipe.preset_names().find("bright"))
	panel.load_saved()
	expect("Save then Load brings back the saved sound", is_equal_approx(panel._sliders[0].value, 0.4) and panel._sliders[2].value == 0.0)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(panel.save_path))

	panel.free()
	inst.free()
	print("all passed" if failed == 0 else "%d FAILED" % failed)
	quit(1 if failed else 0)
