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

- Reduced `JsonCompleter.parse` allocations and improved throughput for long streamed string values by scanning plain string runs in slices instead of per character.

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
