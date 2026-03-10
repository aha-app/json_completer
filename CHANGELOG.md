# Changelog

All notable changes to `json_completer` are documented here.

## Format

- Keep `## [Unreleased]` at the top.
- Use release headers as `## [X.Y.Z] - YYYY-MM-DD`.
- Group entries under `### Added`, `### Changed`, `### Fixed` (optionally `### Removed` / `### Security`).
- Keep entries short and operator/user-facing.

## [Unreleased]

### Added

- Added `JsonCompleter.parse` as the primary incremental streaming API for returning Ruby values directly from partial JSON.
- Added dedicated `ParserEngine`, `CompletionEngine`, and shared `Scanners` components to separate incremental parsing from JSON completion.
- Added parse-focused specs and a streaming benchmark spec.

### Changed

- Expanded benchmark reporting to compare streaming throughput and allocations against `complete + JSON.parse`.

### Fixed

- None.
