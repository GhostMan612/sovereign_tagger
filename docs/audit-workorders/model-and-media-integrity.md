# Audit work orders — Model integrity, folder downloads and recovery verification

**Remote baseline:** `main` at `ba708fe` (2026-11-12)
**Type:** review-only work orders; not implementation claims

## M1 — Size-only speech-model readiness (P1 integrity)

**Evidence:** `lib/core/whistle_model.dart` and `lib/core/whisper_model.dart` treat a file as `isReady` when its length reaches `minBytes`. `ensure()` uses the same size threshold for a bundled/existing model and an HTTP-downloaded `.part`; neither module checks a trusted SHA-256 digest or signed release manifest.

**Impact:** A sufficiently long corrupted, wrong-version or substituted model can be reported ready. It may fail later inside native inference and produce opaque errors, despite a green readiness check.

**Implementation work order:**
1. Pin model identity to an operator-reviewed release artifact and independently verified digest, including source URL, expected byte size, model format and compatibility.
2. Stream SHA-256 over the downloaded `.part` and any preexisting local model before marking ready. Reject mismatch and preserve the previous verified model.
3. Download into unique temporary staging; never truncate a known-good model until the new one passes verification. Support cancellation without deleting the valid prior model.
4. Surface version and digest status in Settings diagnostics; offer explicit re-download.
5. Add offline tests using deterministic synthetic fixture payloads; test corruption, short transfer, cancellation, concurrent ensure calls and recovery after an interrupted rename.

**Do not invent SHA-256 values in code.** This PR deliberately leaves the digest selection for a verified artifact-release step.

## M2 — pCloud folder download silently cuts off traversal (P2 completeness)

**Evidence:** `CloudDownload._collectAudio` stops at recursion depth >3 or when `out.length >= 500`, returning silently. `downloadFolder` therefore reports a summary only for the truncated discovered set. It also calls `onFile?.call('', audio.length, audio.length)` even when the loop was cancelled early, suggesting full progress.

**Implementation work order:**
1. Retain resource limits but return explicit `scanTruncated`, `truncationReason` and `discoveredCount` in the summary.
2. Distinguish enumeration failures from per-file failures, and do not claim a complete folder when the cap applies.
3. On cancellation report `succeeded + failed` processed rather than total; show cancelled state and permit resume.
4. Add tests with a fake `CloudSource`: depth 4, 501 eligible tracks, cancelled at item N, and mid-download failure.

## M3 — Original-content backup completeness is inferred (P1 media safety)

**Evidence:** `StorageBridge.overwriteMedia` copies `openInputStream(uri)` into a `.bak`, checks `bakLen > 0` and hashes the backup. It does not compare the staged backup length/hash against an independently re-read original before opening a destructive `rwt`/`wt` stream. Hashing the backup proves *what was staged*, not necessarily that it captured the full original if the provider returned early without an exception.

**Implementation work order:**
1. Obtain a stable expected source size where available and require equality with `bakLen`; otherwise independently re-read and hash the source before truncation, matching `bakSha`.
2. For content providers that cannot support a stable read, refuse in-place overwrite and offer export-as-new.
3. Ensure journal and backup are durably synced before truncate. Record staging outcome and original source identity.
4. Add fake ContentResolver injection tests for early EOF, short write, readback mismatch, forced process termination and restoration failure.
5. Keep recovery backups until a verified commit or explicit operator discard; never silently classify an unreadable destination as committed.

## M4 — Native destructive-path tests are not in CI (P2 verification gap)

The current GitHub Dart workflow exercises `flutter analyze`, Flutter tests and Python diagnostics. It does not build/run an Android instrumentation harness around MediaStore or the native keychain paths. The on-demand native security self-test covers passphrase encryption and some vault maintenance, not interrupted in-place writes.

**Implementation work order:** Add an Android JVM/instrumentation verification matrix with injectable stream/provider failure modes, disposable test media, and separate minSdk/currentSdk device gates. Run native tests in CI where feasible; record physical hardware runs as independent evidence.

## Merge discipline

Each risk should be implemented and verified in a separate child PR. Do not mark this specification as a functional fix. Avoid modifying users' irreplaceable media during fault injection.
