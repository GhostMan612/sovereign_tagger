---
description: Device smoke checklist + optional release build gate
agent: build
---

Run the Sovereign Tagger smoke gate (Phase 9) as a checklist, not an automatic long build.

1. First run the `/analyze` gate and confirm "No issues found!" — abort if errors exist.
2. Present the device smoke matrix and ask the user to confirm they have a device/emulator ready:
   - Grabber: Quick Video resolution picks (720/1080) + Facebook video mux has audio (probeStreams check)
   - Pipeline: batch cancel + per-item FAILED retry
   - Workbench: loudnorm two-pass + fades/mono/silence round-trips, sample-rate/bit-depth
   - Player: sleep timer, speed, LRC lyrics auto-scroll, queue persist after restart, double-tap ±10s
   - Splash: matrix rain perf (60fps) + AmbientBackdrop not janking on tab swipe
3. Only if the user explicitly confirms, run `flutter build apk --release` and tail the last 20 lines. Otherwise stop after the checklist.
4. Never run the build without explicit user go-ahead — it is device-dependent and slow.
