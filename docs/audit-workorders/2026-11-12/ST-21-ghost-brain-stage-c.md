# ST-21 — Stage C GhostBrain intent/router/index/prompt service extraction

> **Priority:** P3 | **Status:** SPECIFICATION ONLY | **Base:** `0253a994` | **Stage:** C decomposition (mechanical by default)

## Source-supported issue
GhostBrain is ~98 KB, mixing semantic/retrieval routing, tool execution via GhostWorld, intent heuristics and reply formatting; interface default no-op methods should not be mistaken for active capabilities.

- [`lib/services/ghost_brain.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_brain.dart)
- [`lib/services/ghost_world.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_world.dart)
- [`lib/core/embedding_service.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/core/embedding_service.dart)
- [`lib/services/ghost_vector_index.dart`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/lib/services/ghost_vector_index.dart)
- [`.blueprints/ARCHITECTURE_DECOMPOSITION.md`](https://github.com/GhostMan612/sovereign_tagger/blob/0253a994a702cee8b3f834cb8dfb6edd7333fd81/.blueprints/ARCHITECTURE_DECOMPOSITION.md)

## Proposed file/interface changes
- `lib/ghost/ghost_intent_router.dart (new)`
- `lib/ghost/ghost_prompt_templates.dart (new)`
- `lib/ghost/ghost_bm25_index.dart (new if code confirms BM25)`
- `lib/services/ghost_brain.dart`
- `test/ghost_intent_parity_test.dart (new)`

## Surgical extraction phases
1. Create precise call graph for current GhostBrain, GhostWorld implementations and every default method; classify true production actions vs optional/no-op adapter defaults.
2. Extract immutable query normalization and intent rules into a pure tested router; preserve ordering/precedence of overlapping instructions.
3. Move prompt templates, status messages and formatting to typed response schemas; do not add a new hosted LLM or external data transfer.
4. Move any existing BM25/scoring logic only when source confirms; do not assume SQLite storage because blueprint says it exists.
5. Separate execution of side-effectful GhostWorld commands from classification; require explicit user consent for delete/overwrite/download/remote actions.
6. Keep EmbeddingGemmaService and GhostVectorIndex engine epoch/cancellation semantics unchanged and prevent synchronous CPU inference on UI thread.
7. Retain one GhostBrain façade for public call sites; document supported tools, capability responses and nonimplemented defaults without silently pretending action succeeded.

## Tests and negative conditions
- [ ] Golden intent corpus across play, pause, download, metadata, Sentinel, cloud, settings and follow-up choice resolution.
- [ ] Unknown/ambiguous action abstains and no-op default doesn't yield false 'download started' reply.
- [ ] Embedding unavailable native-to-fallback leaves same high-level command capability; forced cancellation keeps side-effect-free parser.

## Acceptance evidence
- [ ] Routing parity under fixture prompts and unchanged public interface.
- [ ] No invented execution success or remote/AI exfiltration.
- [ ] Model memory and latency comparisons captured on Moto G.
- [ ] Source AST/widget/native contract parity independently inspected.
- [ ] Code PR submitted separately with source commit, diff, CI and applicable Android/physical evidence; no Stage C completion claim from doc merge.

## Dependencies / implementation order
ST-11 Ghost play-history decision and ST-12 Sentinel façade; don't conflate with new Ghost feature design.

## Rollback plan
Keep façade and adapter wrappers until parity test green; revert internal extraction without state format change.

## Artifact-chain closeout rules
Use small independent implementation PRs for each file/representation. Record status as `SPEC_ONLY` until code lands. Preserve unrelated workflows, system permissions, app-private data, and the operator preference to finish phase code before running end-of-phase full tests.
