extends PanelContainer
## A small sound panel: presets, one slider per overtone, attack and release, and Save / Load.
## Set `instrument` (the node with modal_instrument.gd) before adding this to the scene. Moving a slider
## changes the instrument's sound at once; the next key you press uses it.
## Save and Load use the file `save_path` (in Godot's user folder).

const Recipe := preload("res://instrument_recipe.gd")
const TONE_NAMES := ["1  the note", "2  octave up", "3  octave + fifth", "4  two octaves", "5  two oct. + third", "6  two oct. + fifth"]

var instrument: Node3D
var save_path := "user://my_sound.json"

var _sliders: Array = []
var _attack: HSlider
var _release: HSlider
var _presets: OptionButton
var _status: Label
var _busy := false    # true while the sliders are set from code, so the sound is rebuilt only once


func _ready() -> void:
	var box := VBoxContainer.new()
	add_child(box)
	var title := Label.new()
	title.text = "Sound"
	box.add_child(title)

	_presets = OptionButton.new()
	_presets.focus_mode = Control.FOCUS_NONE    # no control may take the keyboard: A S D F ... must keep playing
	for preset_name in Recipe.preset_names():
		_presets.add_item(preset_name)
	_presets.item_selected.connect(_on_preset)
	box.add_child(_presets)

	for i in Recipe.HARMONICS:
		_sliders.append(_add_slider(box, "Overtone " + TONE_NAMES[i], 0.0, 1.0, 0.001))
	_attack = _add_slider(box, "Attack (fade in, s)", 0.005, 1.0, 0.005)
	_release = _add_slider(box, "Release (fade out, s)", 0.05, 3.0, 0.01)

	var buttons := HBoxContainer.new()
	box.add_child(buttons)
	for entry in [["Save", save], ["Load", load_saved]]:
		var b := Button.new()
		b.text = entry[0]
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(entry[1])
		buttons.add_child(b)

	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	_status.custom_minimum_size.x = 380
	box.add_child(_status)

	_show(Recipe.preset("warm"))


## The recipe the sliders currently show.
func current_recipe():
	var r = Recipe.new()
	for i in Recipe.HARMONICS:
		r.harmonics[i] = _sliders[i].value
	r.attack_s = _attack.value
	r.release_s = _release.value
	return r


func save() -> void:
	if current_recipe().save_file(save_path):
		_status.text = "Saved: " + ProjectSettings.globalize_path(save_path)
	else:
		_status.text = "Could not save"


func load_saved() -> void:
	var r = Recipe.load_file(save_path)
	if r == null:
		_status.text = "No saved sound found"
		return
	_show(r)
	_apply()
	_status.text = "Loaded"


func _add_slider(parent: Control, text: String, min_v: float, max_v: float, step: float) -> HSlider:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 190
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.custom_minimum_size.x = 190
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(_on_slider_changed)
	row.add_child(slider)
	parent.add_child(row)
	return slider


func _show(r) -> void:
	_busy = true
	for i in Recipe.HARMONICS:
		_sliders[i].value = r.harmonics[i]
	_attack.value = r.attack_s
	_release.value = r.release_s
	_busy = false


func _apply() -> void:
	if instrument:
		instrument.apply_recipe(current_recipe())


func _on_slider_changed(_value: float) -> void:
	if not _busy:
		_apply()


func _on_preset(index: int) -> void:
	_show(Recipe.preset(_presets.get_item_text(index)))
	_apply()
