# Interpreter Lab 0.7.0 (14)

Implements the approved graphite-orb interactive design on top of 0.6.0 (12).

- Replaces the infinity and horizontal dotted waveform with the approved living sphere: graphite volume, internal currents, projected wavy lines, depth-aware particles, thin outer orbit and traveling light.
- Uses real microphone/playback frequency bands, smooth phase transitions, and independent native rendering capped at 30 fps. Pauses offscreen, in background and for Reduce Motion; explicitly resumes on return.
- Shows only the selected partner language in the header. Tapping opens a custom graphite language sheet.
- Recording buttons use dark graphite gradients, a silver rim and immediate touch illumination. Only microphone and source-language name are shown; hold/release/cancel behavior remains native.
- Method, model, speech-engine and language selectors use custom graphite sheets instead of system menus. Voice auditions, account login, saved keys and explicit paid generation remain intact.

Device check: confirm version 0.7.0 (14), switch languages, hold both recording buttons separately, release to translate, interrupt by backgrounding, and return. Inspect sphere smoothness during actual input and playback, not only silence. Check all selection sheets and voice previews. The iPhone bundle remains org.interpreter.lab and uses the existing personal-certificate installation workflow.

Build 14 fixes UIKit placing graphite material above button text/icons and overriding the intended corner radius.
