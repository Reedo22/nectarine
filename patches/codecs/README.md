# Unified multimedia candidate patches

Apply numbered patches to the unified Wine source clone at base
`280cafee40864f6f39a713430ed17c1b5a8cb983`.

1. `0001-winedmo-use-public-ffmpeg-api.patch` removes the build dependency on
   FFmpeg-private AVBSF fields. Big-endian PCM metadata becomes little-endian;
   bytes are reversed only when copying a complete sample to the caller, after
   the capacity check. Misaligned sample data fails instead of reading past its
   end. A PCM MOV decoding regression checks exact output bytes.
2. `0002-winegstreamer-pass-parser-to-autoplug-callback.patch` corrects the
   nested decodebin callback's user data. The callback casts it to `wg_parser`,
   so supplying `wg_parser_stream` reads an unrelated byte as the error flag.
   DirectShow WMV and WM Format decode/EOS probes verify the corrected path.

`gsession*.patch` register `unified-codec`, its default isolated prefix and
engine-local GStreamer environment. This engine's cleanup only sweeps its own
`codecs-*` launch jobs and skips global Steam/game pkill. Other engine defaults
are preserved. `tools/register-codecs.mac.py` makes these changes idempotently
against the current launcher files, preserving parallel agents' edits.

Build/packaging recipes and results: `results/2026-10-28-codecs/README.md`.
