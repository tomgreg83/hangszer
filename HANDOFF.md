# Modal instrument + generative ambient music (Godot first): handoff

Written 2026-11-12 so a fresh Claude session can continue this work. It was split out of a long session that was mostly about a separate app (WhistleToMidi, in `~/Desktop/dev/WhistleToMidi`). Nothing here has to do with the OutRev game: **do not touch `~/Desktop/dev/OutRev`.**

## Who this is for
Tamas is an art director and graphic designer with some coding knowledge, new to music programming and to a lot of dev concepts. Explain in plain language first, details second. Keep answers short, do the literal ask, ask questions when something is vague (he invited that), narrate before running several commands, and don't pad. He is sensitive about wasted effort, extra tools or random workarounds: if something fails, fix the real cause and tell him only what he needs. Tests run headless only, with a wall-clock watchdog, one or two processes at a time.

## The idea
A VR app (Godot, maybe also a GameMaker game later) with:
1. **A keyed instrument** the player holds. Pressing a key plays the right pitch, in a chosen key and mode.
2. **Generative ambient background music** that plays notes and harmonies almost randomly under a rule set, in a chosen mode. There is no single mood: **the mood comes from the mode** (Lydian bright/floating, Mixolydian relaxed/open, Dorian warm, Aeolian sad, Phrygian dark/tense, Locrian unstable). Style: a couple of sweeping pad layers plus some other sparse sounds.

## Music basics already explained to him (keep consistent)
- Pitch is a ratio. An octave doubles the frequency. Equal temperament splits the octave into 12 equal steps, each x 2^(1/12) = 1.0595. `Hz = 130.81 x 2^(steps/12)` from C3 (negative steps go down, i.e. divide by 1.0595 per step). A4 = 440 Hz is a convention; octave numbering varies (middle C = C4 here).
- MIDI note n: `Hz = 440 x 2^((n-69)/12)`.
- Modes are step lists in semitones: ionian 0,2,4,5,7,9,11; dorian 0,2,3,5,7,9,10; phrygian 0,1,3,5,7,8,10; lydian 0,2,4,6,7,9,11; mixolydian 0,2,4,5,7,9,10; aeolian 0,2,3,5,7,8,10; locrian 0,1,3,5,6,8,10.
- Harmony that stays in the mode moves by scale steps, not fixed semitones (a third above = two scale steps up). Chords = every other scale step.
- Just intonation (pure ratios like 3/2) vs equal temperament: optional, interesting for modal/ambient work. Cents = 1/100 semitone.
- Changing pitch of a sound: generate from a note number, or play a sample faster/slower (`pitch_scale` ratio 2^(semitones/12)); keeping length while shifting needs special algorithms (Rubber Band etc.).

## Handoff design for game engines (agreed direction)
Not MIDI and not a separate program. Three things:
1. A **rules file (JSON)**: modes, how often to step vs leap, rest probability, note lengths, chord patterns as scale degrees (e.g. 1-4-5), tempo range. Both Godot and GameMaker read JSON natively.
2. A **small generator script per engine** (about 100 lines): keeps the current scale degree, favours small moves, returns to the home note now and then, converts degree -> semitone -> pitch ratio. GDScript first; GML port later.
3. **Samples** he makes in Bitwig.

## Godot facts checked (4.7.1.stable, headless probe)
`AudioStreamPlayer3D` (has `pitch_scale`, `max_polyphony`), `AudioStreamWAV`, `AudioStreamGenerator`, `AudioStreamPolyphonic`, `AudioStreamRandomizer`, `XRController3D`, `XRHandModifier3D` all exist. **No `AudioStreamMIDI`** (no built-in MIDI file playback). `OS.open_midi_inputs` exists. Godot: `/Applications/Godot.app/Contents/MacOS/Godot`.

## What exists here
- `modal_instrument.gd`: a `Node3D` script. Children `Area3D` = keys, left to right. Exports: `mode`, `root_note` (MIDI note of first key; 50 = D3), `samples` (`Dictionary[int, AudioStream]`: MIDI note the sample was recorded at -> sound; each key uses the nearest and is pitch-scaled), `keys_parent`, `finger_group` (default `finger`), `volume_db`, `attack_s`, `release_s`, `keyboard_test` (A S D F G H J K L ; press keys 0-9 on a flat screen). Signals `note_on(midi_note, key_index)` / `note_off`. Public `press(key, velocity)`, `release(key)`, `retune()`, `note_for_key`, static `note_to_hz`, `make_tone`. With no samples it generates a looping soft tone in code (260 Hz exactly, whole cycles, so it loops cleanly) and pitch-scales it. Touch: any node in group `finger` entering a key's `Area3D` (body or area) presses it; two fingers on one key release only when both leave.
- `test_modal_instrument.gd`: headless test, 18 checks passing. Run: `perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script test_modal_instrument.gd`
- `project.godot`: minimal, so the folder runs headless and opens in Godot.
- Not yet heard in VR or by ear; the generated tone is a placeholder.

## Decisions and answers from Tamas
- Separate project from OutRev. (The folder `GodotInstrument` is just where it landed; ask if he wants it moved or renamed.)
- No finger-tracking gear yet: **test with controllers**. Plan: a small sphere `Area3D` on each controller tip, in group `finger`; finger tracking later puts the same kind of node on fingertips, so the instrument script does not change. Possible extra: a haptic buzz on `note_on`.
- **Samples are his own, made in Bitwig.** Advice given: export WAV; **pad samples should be single sustained notes, not chords** (so the generator builds chords from the mode); roughly one sample per octave; name files with the note, e.g. `pad_C3.wav`. Idea offered, not built: load a whole folder and fill `samples` from the file names.
- Self-generated sound: the built-in tone already counts. Richer generated sound is incremental (more waveforms, envelope settings, Godot's built-in audio bus effects such as reverb: verify the class names in 4.7 before using). A full synth engine is optional and bigger.

## Questions answered (2026-11-12)
1. Who changes the mode: normally the game (event, time or place); easy to hand to the player later.
2. Keys following the background mode: not required for now.
3. Layers: two pads plus one sparse sound.
He also said: this is only the basics; he is not sure how the app will go. **Keep it a simple baseline he can understand and see through: Godot, an instrument object (VR or not). Don't plan or build ahead of what he asks.**

## Built after those answers
- `music_state.gd`: a tiny Node holding `mode` and `root_note` (emits `changed`), plus `degree_to_note` (the mode maths, moved here from the instrument), `note_to_hz`, `is_in_scale`.
- `modal_instrument.gd` has an optional `state` export: if set, the keys follow it; if empty, nothing changes from before.
- `test_music_state.gd`: headless, all passed (prints each mode's notes from C and checks them). Run it the same way as the other test.

## Where this lives (2026-11-20)
- The folder was renamed `Instrument` and sits inside `~/Desktop/dev/The Cosmic Key/`, but it is its **own git repo**: `git@github.com:tomgreg83/hangszer.git` (private; "hangszer" is Hungarian for instrument), branch `main`. The Cosmic Key game is a separate repo; do not mix them.
- Tamas wants to continue on other computers and on his phone (a Claude cloud session on this repo). Commit and push before switching devices; pull on the other one.
- The test commands in this file point at the Mac's Godot (`/Applications/Godot.app/...`). A cloud session may not have Godot; say so rather than working around it.

## Sound recipe + sound panel (2026-11-21, built in a cloud session, NOT YET RUN)
Tamas said go. Built without Godot (the cloud session has none), so **run the tests on the Mac first**:
`perl -e 'alarm 60; exec @ARGV' /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script test_recipe.gd`
and re-run the other three tests, since `modal_instrument.gd` and `demo.gd` changed.
- `instrument_recipe.gd`: a recipe = 6 overtone volumes (0-1), `attack_s`, `release_s`. Five presets (warm = the original tone, soft, bright, hollow, pure). Saves/loads JSON.
- `modal_instrument.gd`: new `apply_recipe(recipe)`; `make_tone(harmonics)` takes the volumes (no argument = the original tone, unchanged), with a gain limit so loud settings never clip. Affects only the generated tone, not recorded `samples`. A key already held keeps its old tone until pressed again (a player's stream is reset by `retune()`; not checked whether that cuts a held note).
- `recipe_panel.gd`: panel with preset menu, 6 overtone sliders, attack, release, Save/Load (file `user://my_sound.json`). Controls do not take keyboard focus, so A S D F ... keep playing. Added to the top right in `demo.gd`.
- `test_recipe.gd`: headless test of all of the above.
- Not checked: how the panel looks (layout/overlap with the label), and how it sounds.

## Demo scene to hear it (2026-11-13)
- `demo.tscn` (the project's main scene) + `demo.gd`: 10 box keys, a camera, a `MusicState` node the instrument is linked to, a label. Play with A S D F G H J K L ; and switch mode with number keys 1-7. Run: `/Applications/Godot.app/Contents/MacOS/Godot --path ~/Desktop/dev/GodotInstrument` or open the folder in Godot and press F5.
- `test_demo.gd`: headless, 14 checks passing. It puts an `AudioEffectCapture` on the Master bus and measures the level and pitch of the real output (works with the headless Dummy audio driver): A = D3 146.83 Hz, lydian's 4th key = G#3 207.65 Hz, five notes together peak 0.62.
- Found and fixed through that test: `AudioStreamPlayer3D` defaults to `unit_size = 10` (normal volume at 10 m), so keys 1 m away were boosted until chords clipped. The instrument now sets `unit_size = 1.0` and `max_db = 0.0` on each key's player.
- Tamas has not yet confirmed hearing it in a window; the sound is still the generated placeholder tone.

## Proposed next steps (only step 1 is built; wait for his go on each)
1. (done, see above) A shared **music state** (home note + mode) that both the instrument and the generator read.
2. A **pad layer**: slow chord movement within the current mode, built from single-note pad samples.
3. A **sparse layer** (occasional bell/notes), and a smooth cross-fade when the mode changes.
4. Rules in JSON; a headless test that prints the notes the generator would play for a given mode and checks them.
5. Sample-folder loader; controller tip piece (with optional haptics).
6. Later: the same generator in GML for GameMaker.

Check what Godot 4.7 already offers before writing any custom mechanism, and say what was checked.
