# Changelog

All notable changes to `json_completer` are documented here.

## Format

- Keep `## [Unreleased]` at the top.
- Use release headers as `## [X.Y.Z] - YYYY-MM-DD`.
- Group entries under `### Added`, `### Changed`, `### Fixed` (optionally `### Removed` / `### Security`).
- Keep entries short and operator/user-facing.

## [Unreleased]

### Added

- None.

### Changed

- `JsonCompleter#parse` now follows the same append-only incremental contract as `#complete`: growing inputs stay on the hot path, and callers should create a new instance if earlier bytes change.
- Reduced `JsonCompleter.parse` allocations and improved throughput on append-only streaming inputs by walking the hot path as bytes and keeping string-copy work slice-based.

### Fixed

- None.

## [1.1.0] - 2026-03-11

### Added

- `JsonCompleter.parse` and `JsonCompleter#parse` — incremental streaming API that returns parsed Ruby values directly from partial JSON, avoiding an extra `JSON.parse` round-trip.
- `ParserEngine`, `CompletionEngine`, and `Scanners` extracted as dedicated internal components for incremental parsing and completion.
- Parse-focused spec suite and streaming benchmark spec (`parse_benchmark_spec.rb`).

### Changed

- `.parse` is now the recommended primary API; `.complete` is repositioned for cases where downstream consumers specifically need JSON text.
- README rewritten to lead with `.parse`, highlight LLM streaming use cases (OpenAI, Anthropic), and document `.complete` as the text-output alternative.
- Benchmark reporting expanded to compare streaming throughput and allocations against `complete + JSON.parse`.
