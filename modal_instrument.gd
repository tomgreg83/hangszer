extends Node3D
## A keyed instrument that plays in a musical mode (Dorian, Lydian, ...), for a VR or flat Godot 4 project.
##
## Setup: put this script on a Node3D. Give that node (or the node in `keys_parent`) one Area3D child per
## key, in left-to-right order, each with a CollisionShape3D. The first key plays `root_note`, and the
## following keys climb through the scale of `mode`. When a node in the group `finger_group` (give your
## hand-tracking fingertip bodies or controller tip areas that group) touches a key, the note sounds, and it
## fades out when the finger leaves. Any other VR interaction can call press(key) / release(key) directly.
##
## With no sound files, one soft tone is generated in code and played faster or slower for each note.
## With recorded sounds in `samples`, each key plays the nearest recording instead, sped up or slowed down.

signal note_on(midi_note: int, key_index: int)    # hook sound effects, key animation or haptics here
signal note_off(midi_note: int, key_index: int)

const MusicState := preload("res://music_state.gd")    # the modes and the degree -> note maths live there

## Whole cycles in the generated tone, so it loops with no click. 26 cycles in 4410 frames at 44100 Hz = exactly 260 Hz.
const SAMPLE_RATE := 44100
const SAMPLE_FRAMES := 4410
const SAMPLE_CYCLES := 26
const SAMPLE_HZ := SAMPLE_CYCLES * float(SAMPLE_RATE) / SAMPLE_FRAMES
## For testing on a flat screen without VR: these keyboard keys press keys 0, 1, 2, ...
const KEYBOARD_TEST_KEYS := [KEY_A, KEY_S, KEY_D, KEY_F, KEY_G, KEY_H, KEY_J, KEY_K, KEY_L, KEY_SEMICOLON]

@export_enum("ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian", "chromatic") var mode: String = "dorian":
	set(value):
		mode = value
		retune()
## MIDI note of the first key: 48 = C3, 50 = D3, 60 = middle C. This also sets the key (the home note) of the scale.
@export var root_note: int = 50:
	set(value):
		root_note = value
		retune()
## Your recorded sounds, as: the MIDI note the sound was recorded at -> the sound (WAV or OGG). Every key uses the
## nearest one and plays it faster or slower to reach its note, so a few recordings (say one per octave) cover the
## whole instrument. Leave empty to use the built-in generated tone. For a sustained pad, switch on Loop in the
## sound's Import settings. After changing this while the game runs, call retune().
@export var samples: Dictionary[int, AudioStream] = {}:
	set(value):
		samples = value
		retune()
## The Area3D keys are this node's children; leave empty to use the node the script is on.
@export var keys_parent: Node3D
## Optional. Give it the shared MusicState node and the keys follow its mode and home note whenever they change.
## Leave empty and the keys use this node's own `mode` and `root_note`.
@export var state: Node
@export var finger_group: StringName = &"finger"
@export var volume_db: float = -8.0
@export var attack_s: float = 0.02
@export var release_s: float = 0.35
@export var keyboard_test: bool = true

var _tone: AudioStreamWAV
var _harmonics: Array = []          # overtone volumes from the last recipe; empty = the original tone
var _players: Array[AudioStreamPlayer3D] = []
var _touching: Array[int] = []      # fingers currently on each key
var _down: Array[bool] = []
var _tweens: Array = []


func _ready() -> void:
	_tone = make_tone(_harmonics)
	for child in (keys_parent if keys_parent else self).get_children():
		if child is Area3D:
			_add_key(child)
	if state:
		state.changed.connect(_follow_state)
		_follow_state()
	else:
		retune()


func _follow_state() -> void:
	mode = state.mode
	root_note = state.root_note


## Frequency of a MIDI note (69 = A4 = 440 Hz). Every octave doubles it; every semitone multiplies it by 2^(1/12).
static func note_to_hz(midi_note: int) -> float:
	return MusicState.note_to_hz(midi_note)


## The MIDI note a key plays: climbs through the mode's steps, then repeats an octave higher.
func note_for_key(key: int) -> int:
	return MusicState.degree_to_note(root_note, mode, key)


func press(key: int, velocity: float = 1.0) -> void:
	if key < 0 or key >= _players.size() or _down[key]:
		return
	_down[key] = true
	_players[key].volume_db = -60.0
	_players[key].play()
	_fade(key, volume_db + linear_to_db(clampf(velocity, 0.05, 1.0)), attack_s, false)
	note_on.emit(note_for_key(key), key)


func release(key: int) -> void:
	if key < 0 or key >= _players.size() or not _down[key]:
		return
	_down[key] = false
	_fade(key, -60.0, release_s, true)
	note_off.emit(note_for_key(key), key)


## Gives every key its sound and its pitch. Called by itself when `mode`, `root_note` or `samples` is set.
func retune() -> void:
	for key in _players.size():
		var note := note_for_key(key)
		var stream: AudioStream = _tone
		var base_hz := SAMPLE_HZ
		if not samples.is_empty():
			var recorded_at := _nearest_sample_note(note)
			stream = samples[recorded_at]
			base_hz = note_to_hz(recorded_at)
		_players[key].stream = stream
		var ratio := note_to_hz(note) / base_hz
		if ratio < 0.01 or ratio > 4.0:
			push_warning("Key %d is out of range for its sound; add a sample nearer to it, or change root_note." % key)
		_players[key].pitch_scale = clampf(ratio, 0.01, 4.0)


func _nearest_sample_note(note: int) -> int:
	var best := -1
	for recorded_at in samples:
		if best < 0 or absi(recorded_at - note) < absi(best - note):
			best = recorded_at
	return best


## Uses a sound recipe (see instrument_recipe.gd): rebuilds the generated tone from its overtone volumes and
## takes over its attack and release. Only affects the generated tone; recorded `samples` keep their own sound.
func apply_recipe(recipe) -> void:
	_harmonics = recipe.harmonics.duplicate()
	attack_s = recipe.attack_s
	release_s = recipe.release_s
	_tone = make_tone(_harmonics)
	retune()


## One soft tone as a looping sound: the volumes of overtones 1, 2, 3, ... (up to 6). With none given, the
## original tone, each overtone 1/h^2 as loud as the first. The total is kept so loud settings never clip.
static func make_tone(harmonics: Array = []) -> AudioStreamWAV:
	var weights: Array = harmonics.duplicate()
	if weights.is_empty():
		for h in range(1, 7):
			weights.append(1.0 / (h * h))
	var total := 0.0
	for w in weights:
		total += absf(w)
	var gain := minf(0.55, 0.9 / maxf(total, 0.0001))
	var data := PackedByteArray()
	data.resize(SAMPLE_FRAMES * 2)
	for i in SAMPLE_FRAMES:
		var phase := TAU * SAMPLE_CYCLES * i / SAMPLE_FRAMES
		var v := 0.0
		for h in weights.size():
			v += weights[h] * sin(phase * (h + 1))
		data.encode_s16(i * 2, int(clampf(v * gain, -1.0, 1.0) * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = SAMPLE_FRAMES
	return wav


func _add_key(area: Area3D) -> void:
	var key := _players.size()
	var player := AudioStreamPlayer3D.new()
	player.stream = _tone
	player.volume_db = -60.0
	player.unit_size = 1.0             # `volume_db` is how loud a key is from 1 metre (Godot's default is 10 m,
	player.max_db = 0.0                # which makes a hand-held instrument far too loud), and never louder up close
	area.add_child(player)             # the sound comes from the key's own position
	_players.append(player)
	_touching.append(0)
	_down.append(false)
	_tweens.append(null)
	area.body_entered.connect(_on_touch.bind(key, 1))
	area.area_entered.connect(_on_touch.bind(key, 1))
	area.body_exited.connect(_on_touch.bind(key, -1))
	area.area_exited.connect(_on_touch.bind(key, -1))


func _on_touch(other: Node, key: int, change: int) -> void:
	if not other.is_in_group(finger_group):
		return
	_touching[key] = maxi(0, _touching[key] + change)    # two fingers on one key: it lets go when both have left
	if change > 0 and _touching[key] == 1:
		press(key)
	elif change < 0 and _touching[key] == 0:
		release(key)


func _fade(key: int, to_db: float, seconds: float, stop_after: bool) -> void:
	if _tweens[key] != null:
		_tweens[key].kill()
	var tween := create_tween()
	_tweens[key] = tween
	tween.tween_property(_players[key], "volume_db", to_db, seconds)
	if stop_after:
		tween.tween_callback(_players[key].stop)


func _unhandled_key_input(event: InputEvent) -> void:
	var e := event as InputEventKey
	if not keyboard_test or e == null or e.echo:
		return
	var key := KEYBOARD_TEST_KEYS.find(e.physical_keycode)
	if key >= 0:
		if e.pressed:
			press(key)
		else:
			release(key)
