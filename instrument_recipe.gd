extends RefCounted
## A sound recipe for the generated tone: how loud each of the 6 overtones is, plus attack (fade in) and
## release (fade out). A recipe can be saved to and loaded from a small JSON file.
##
## Overtone 1 is the note itself, 2 is an octave above, 3 an octave and a fifth, and so on. Louder high
## overtones make the sound brighter; only the first makes it a pure, flute-like tone.

const HARMONICS := 6
const PRESET_NAMES := ["warm", "soft", "bright", "hollow", "pure"]

## Volume of overtones 1..6, each from 0 (silent) to 1 (full).
var harmonics: Array = []
## Seconds to fade in when a key is pressed.
var attack_s: float = 0.02
## Seconds to fade out when a key is let go.
var release_s: float = 0.35


func _init() -> void:
	for h in range(1, HARMONICS + 1):
		harmonics.append(1.0 / (h * h))    # the original tone: each overtone quieter than the one before


static func preset_names() -> Array:
	return PRESET_NAMES


## One of PRESET_NAMES. Anything else gives the "warm" original tone.
static func preset(preset_name: String):
	var r = load("res://instrument_recipe.gd").new()
	match preset_name:
		"soft":      # mostly the note itself, slow and gentle
			r.from_dict({"harmonics": [1.0, 0.12, 0.03, 0.0, 0.0, 0.0], "attack_s": 0.08, "release_s": 0.5})
		"bright":    # strong overtones, quick
			r.from_dict({"harmonics": [1.0, 0.8, 0.6, 0.45, 0.35, 0.25], "attack_s": 0.01, "release_s": 0.3})
		"hollow":    # odd overtones only, a clarinet-like sound
			r.from_dict({"harmonics": [1.0, 0.0, 0.33, 0.0, 0.2, 0.0], "attack_s": 0.03, "release_s": 0.3})
		"pure":      # a single clean tone
			r.from_dict({"harmonics": [1.0, 0.0, 0.0, 0.0, 0.0, 0.0], "attack_s": 0.05, "release_s": 0.6})
	return r


func to_dict() -> Dictionary:
	return {"harmonics": harmonics.duplicate(), "attack_s": attack_s, "release_s": release_s}


## Reads values from a dictionary. Missing or odd entries keep their current value; numbers are kept in range.
func from_dict(d: Dictionary) -> void:
	var h = d.get("harmonics", null)
	if h is Array:
		for i in mini(h.size(), HARMONICS):
			harmonics[i] = clampf(_number(h[i], harmonics[i]), 0.0, 1.0)
	attack_s = clampf(_number(d.get("attack_s", null), attack_s), 0.005, 1.0)
	release_s = clampf(_number(d.get("release_s", null), release_s), 0.05, 3.0)


func save_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "\t"))
	return true


## A recipe read from a JSON file, or null if the file is missing or is not a recipe.
static func load_file(path: String):
	if not FileAccess.file_exists(path):
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return null
	var r = load("res://instrument_recipe.gd").new()
	r.from_dict(parsed)
	return r


static func _number(value, fallback: float) -> float:
	if value is float or value is int:
		return float(value)
	return fallback
