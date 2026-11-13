extends Node3D
## Flat-screen demo, to hear the instrument without VR.
## Play notes with  A S D F G H J K L ;   Switch mode with the number keys 1-7.

const MODE_NAMES := ["ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian"]
const NOTE_NAMES := ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

@onready var state: Node = $MusicState
@onready var instrument: Node3D = $Instrument
@onready var label: Label = $Label


func _ready() -> void:
	instrument.note_on.connect(func(_note, key): instrument.get_child(key).position.y = -0.02)    # the key dips
	instrument.note_off.connect(func(_note, key): instrument.get_child(key).position.y = 0.0)
	state.changed.connect(_show_mode)
	_show_mode()


func _show_mode() -> void:
	label.text = "%s %s\n\nPlay:  A S D F G H J K L ;\nMode:  1 ionian  2 dorian  3 phrygian  4 lydian  5 mixolydian  6 aeolian  7 locrian" % [
		NOTE_NAMES[posmod(state.root_note, 12)], state.mode]


func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if e == null or not e.pressed or e.echo:
		return
	var number := e.physical_keycode - KEY_1    # 0 for the "1" key, 1 for "2", ...
	if number >= 0 and number < MODE_NAMES.size():
		state.mode = MODE_NAMES[number]
