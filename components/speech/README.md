# Nectarine SAPI speech prototype

This folder contains an x86-64 Wine builtin DLL and matching x86-64 macOS
Unixlib prototype. The DLL implements `ISpTTSEngine` and
`ISpObjectWithToken`; the Unixlib enumerates macOS voices and synthesizes
mono PCM through `AVSpeechSynthesizer`. It does not shell out to `say`.

The candidate was run in a cloned Wine engine and isolated prefix. Its Unixlib
must be installed beside the candidate Wine engine's `lib/wine/x86_64-unix`
modules and the PE builtin beside `lib/wine/x86_64-windows` modules; do not add
either binary to the live `wine11` bundle. The exact tested binaries are
preserved in `results/2026-10-22-agent-push/speech/artifacts/`, with hashes
there recorded by the test report. Source and candidate results are under this
repository's `components/speech/` and `results/2026-10-22-agent-push/speech/`.

## Evidence

- Registration enumerated 180 native macOS voices and selected a default.
- `ISpVoice::Speak` to an `ISpStream` returned 98,596 bytes of nonzero mono
  PCM. The saved WAV is 22.05 kHz, 16-bit, mono, 2.236 seconds.
- Repeated speech and selecting a second voice both returned nonzero PCM.
- The current integration gate is **not complete**. After
  `SPF_PURGEBEFORESPEAK`, Wine reports `WaitUntilDone` success while status
  remains SPEAKING, and the native job is not freed until releasing the voice.
  See `sapi-integration-candidate-engine.log` and
  `sapi-integration-poll.log`. The source currently lacks evidence for reliable
  abort/idle lifecycle and unload behavior.
- Wine's `SpInprocRecognizer` remains unregistered. There is no speech
  recognition provider in this prototype.

The sample build commands were not captured during the remote candidate build,
so this prototype is source reviewable but not yet a reproducible build/install
package. It must remain isolated until build instructions and the abort/unload
tests are complete.
