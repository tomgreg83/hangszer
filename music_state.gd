extends Node
## The one shared answer to "what key and mode are we in right now?"
##
## Add this as a node (or an autoload). The game sets `mode` / `root_note` when something happens (an event, the
## time, a place, or the player); everything that makes music reads it and listens to `changed`.
## A scale "degree" counts steps through the mode: 0 is the home note, 1 the next scale note, 7 the home note an
## octave up, -1 the scale note just below home.

signal changed

## The steps (in semitones above the home note) of each mode.
const MODES := {
	"ionian": [0, 2, 4, 5, 7, 9, 11],
	"dorian": [0, 2, 3, 5, 7, 9, 10],
	"phrygian": [0, 1, 3, 5, 7, 8, 10],
	"lydian": [0, 2, 4, 6, 7, 9, 11],
	"mixolydian": [0, 2, 4, 5, 7, 9, 10],
	"aeolian": [0, 2, 3, 5, 7, 8, 10],
	"locrian": [0, 1, 3, 5, 6, 8, 10],
	"chromatic": [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11],
}

@export_enum("ionian", "dorian", "phrygian", "lydian", "mixolydian", "aeolian", "locrian", "chromatic") var mode: String = "dorian":
	set(value):
		if value != mode:
			mode = value
			changed.emit()
## MIDI note of the home note: 48 = C3, 50 = D3, 60 = middle C.
@export var root_note: int = 50:
	set(value):
		if value != root_note:
			root_note = value
			changed.emit()


## The MIDI note for a scale degree, in any home note and mode. Degrees below 0 or above the octave work too.
static func degree_to_note(home: int, scale_mode: String, degree: int) -> int:
	var steps: Array = MODES[scale_mode]
	return home + floori(degree / float(steps.size())) * 12 + steps[posmod(degree, steps.size())]


## Frequency of a MIDI note (69 = A4 = 440 Hz). Every octave doubles it; every semitone multiplies it by 2^(1/12).
static func note_to_hz(midi_note: int) -> float:
	return 440.0 * pow(2.0, (midi_note - 69) / 12.0)


func note_for_degree(degree: int) -> int:
	return degree_to_note(root_note, mode, degree)


## True if a MIDI note belongs to the current scale (in any octave).
func is_in_scale(midi_note: int) -> bool:
	return MODES[mode].has(posmod(midi_note - root_note, 12))
