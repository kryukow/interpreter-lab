# Interpreter Lab 0.6.0 (12)

Based on 0.5.0 (11). App icon, language orbit, signing identity and saved settings remain compatible.

- Separate audition and selection for Apple voices and ElevenLabs account voices.
- Search the public ElevenLabs voice library in Polish, English, Spanish, Russian, German and Romanian. Play an existing demo before adding a voice. Previewing never calls paid text-to-speech; adding a voice requires an explicit button press.
- Display loading, playback and failure states; stop previews when leaving the screen or the app.
- Fix the public-voice import URL and retain selected voice names in settings summaries.
- Collapsible graphite settings cards summarize translation method/model, account, voice selections, generation model and automatic paid generation.
- Cosmic graphite light, fine dust lanes and orbital particles; distinct idle, recording, processing and playback motion, smooth intensity changes and explicit foreground recovery.
- Live monospaced transcription shows the current recognizer hypothesis without fake delays. Follow the newest words, scroll back manually, or return with “К текущим словам”. Recording controls stay at the bottom.

## Device checks

1. Install with the existing personal-certificate IPA workflow. Confirm 0.6.0 (12) in the app.
2. Open Settings → Голос. Audition two Apple voices; neither should become selected until “Выбрать”. Check a system-default voice too.
3. Choose ElevenLabs, load account voices, then open the library. Try Polski, English and Español. Play/stop several demos before selecting. Demos should not consume TTS credits. A general demo may be in another language; the app labels that case.
4. Add a voice explicitly. Check the selected name, return to the app, then reopen settings. Some public voices require an eligible ElevenLabs plan and Voices Write permission.
5. Keep paid auto-generation off unless you want it. Translate, then explicitly generate speech. Confirm the selected provider and credit behavior in your account.
6. Speak for over a minute; watch the newest words. Scroll up to inspect earlier text, then tap “К текущим словам”. Confirm that the whole accumulated phrase is translated.
7. Move the app to background, return, lock/unlock, and open/close settings. The orbit must keep moving after each return.
8. Observe idle → press/arming → recording → processing → playback → idle. Check smooth motion on a physical iPhone and with Reduce Motion enabled.

Simulator tests and successful packaging cannot establish actual microphone quality, ElevenLabs account permissions, voice availability or physical-device frame rate.
