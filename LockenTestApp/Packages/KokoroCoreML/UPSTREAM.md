# Upstream

- Source: https://github.com/Jud/kokoro-coreml
- Version: tag v0.11.2, commit 6bfc02afb237a311caee927482e58c028edb6acb
- License: Apache-2.0 (LICENSE, unchanged)
- Vendored on 2026-10-20 because the release build is universal (Apple silicon and Intel) and upstream
  doesn't compile for Intel: `Float16` is unavailable on x86_64 macOS.

## Locken's changes
1. `Package.swift`: library target only; the CLI, tests and their dependencies (swift-argument-parser, cbor)
   removed; `swift-bart-g2p` pinned to exactly 0.4.0.
2. `Sources/KokoroCoreML/MLArrayHelpers.swift`: on Intel, float16 output is converted with
   `vImageConvert_Planar16FtoPlanarF` instead of the `Float16` type. Apple silicon is unchanged.
3. Removed files not needed to build the library: Examples, docs, research, scripts, Tests, Sources/CLI, CI config.

Voice files are not part of this package; the app downloads them on request (see VoiceAssistant.swift).
