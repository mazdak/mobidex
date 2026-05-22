# OpenAI Transcription Architecture

## Research Notes

- OpenAI's speech-to-text guide lists `transcriptions` and `translations` as the Audio API speech-to-text endpoints. The current transcription models include `gpt-4o-mini-transcribe`, `gpt-4o-transcribe`, and `gpt-4o-transcribe-diarize`, alongside `whisper-1`.
- File-based transcription is bounded by the Audio API upload path. OpenAI documents a 25 MB upload limit for `mp3`, `mp4`, `mpeg`, `mpga`, `m4a`, `wav`, and `webm` inputs.
- `gpt-4o-transcribe` and `gpt-4o-mini-transcribe` support `json` or plain `text` output. `gpt-4o-transcribe-diarize` supports speaker-aware `diarized_json` and needs `chunking_strategy` for audio longer than 30 seconds.
- Realtime transcription emits incremental `conversation.item.input_audio_transcription.delta` events and final `conversation.item.input_audio_transcription.completed` events. OpenAI explicitly calls out a latency/accuracy tradeoff controlled by transcription delay settings.
- Sources checked: https://developers.openai.com/api/docs/guides/speech-to-text, https://developers.openai.com/api/reference/resources/audio/subresources/transcriptions/methods/create, and https://developers.openai.com/api/docs/guides/realtime-transcription.

## Product Shape

Mobidex should start with push-to-record transcription that inserts text into the current chat composer. That keeps audio as an input convenience, not a second chat protocol, and it composes cleanly with the per-chat draft model:

1. User taps the `+` menu and chooses `Record Audio`.
2. Native client records a short local audio file.
3. Client uploads the audio to a Mobidex-owned transcription service.
4. Service calls OpenAI `audio/transcriptions`.
5. Client appends the returned text to the current composer draft for the active chat key.
6. User can edit the transcript before submitting to Codex.

Brand new chats use the same draft key fallback as text input: server plus selected project until a thread exists, then server plus thread.

## Architecture

Keep OpenAI credentials out of native clients. Add a small server endpoint:

- `POST /v1/transcriptions`
- Auth: Mobidex app auth/session token, not an OpenAI API key.
- Request: multipart audio file plus optional `language`, `prompt`, and `mode`.
- Response: `{ "text": "...", "duration_ms": ..., "model": "gpt-4o-transcribe" }`.

Default model should be `gpt-4o-transcribe` for composer dictation because short voice snippets are latency- and cost-bounded, while transcription mistakes directly affect the coding prompt. Keep `gpt-4o-mini-transcribe` as a future low-cost option if usage volume makes that tradeoff worthwhile. Reserve `gpt-4o-transcribe-diarize` for a later meeting/transcript feature because composer dictation does not need speaker labels.

Native responsibilities:

- iOS: `AVAudioRecorder` or `AVAudioEngine` records `m4a`, requests microphone permission, shows recording duration, and writes to temporary storage.
- Android: `MediaRecorder` records `m4a` or `mp4`, requests `RECORD_AUDIO`, shows recording duration, and writes to cache.
- Both clients attach transcript text to the active composer draft rather than directly sending a message.
- Both clients delete local audio after successful upload or explicit cancellation.

Server responsibilities:

- Enforce audio size and duration limits before calling OpenAI.
- Normalize/validate MIME type and extension.
- Call `audio/transcriptions` with `response_format=text` or `json`.
- Add request timeout, retry only on transient transport failures, and return user-readable errors.
- Avoid persisting audio by default; if logs need troubleshooting metadata, store duration, size, model, status, and request ID only.

## Follow-Up Decisions Before Coding

- Hosting location for the Mobidex transcription service.
- User-visible consent/privacy copy for microphone use and transient upload.
- Exact recording cap. A practical starting point is 60 seconds or 20 MB, comfortably under the documented 25 MB upload limit.
- Whether audio transcription should appear as `Record Audio` under the same `+` menu immediately, or behind a settings flag until backend auth exists.
