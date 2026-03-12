# Release runbook

This is the canonical manual release procedure for `json_completer`.

## Scope

- Release source: `main`
- Publish target: RubyGems package `json_completer`
- Release tag format: `vX.Y.Z`
- Release automation: none

## Changelog format

`CHANGELOG.md` must always contain:

- `## [Unreleased]`
- Version sections formatted as `## [X.Y.Z] - YYYY-MM-DD`
- Structured subsections (`Added`, `Changed`, `Fixed`, optional `Removed` / `Security`)

## Common publish flow

The common laptop flow for a Ruby gem is:

1. Update release metadata locally.
2. Run the full local validation gate.
3. Tag the release in git.
4. Build the gem with `gem build`.
5. Publish it with `gem push`.
6. Verify the published version from RubyGems.

That is the flow this repo uses.

## Release steps

1. Prepare `main`
   - Make sure `main` is up to date and clean enough for a release.
   - Confirm `CHANGELOG.md` under `## [Unreleased]` reflects what will ship.

2. Cut the release metadata
   - Move completed entries from `## [Unreleased]` into a new section:
     - `## [X.Y.Z] - YYYY-MM-DD`
   - Reset `## [Unreleased]` back to placeholders.
   - Bump `spec.version` in `json_completer.gemspec` to `X.Y.Z`.
   - Sync `Gemfile.lock` immediately after the version bump so the path gem version matches the gemspec:
     ```bash
     bundle install
     ```
   - Verify `Gemfile.lock` now shows `json_completer (X.Y.Z)` under the `PATH` section before committing or tagging.

3. Run the required validation
   - `bundle exec rubocop`
   - `bundle exec rspec`
   - `JSON_COMPLETER_BENCHMARK=1 bundle exec rspec spec/parse_benchmark_spec.rb`

4. Commit the release
   - Commit the version, lockfile, and changelog updates on `main`.
   - Example:
     ```bash
     git add json_completer.gemspec Gemfile.lock CHANGELOG.md
     git commit -m "chore: release vX.Y.Z"
     ```

5. Tag the release
   - Run:
     ```bash
     git tag -a vX.Y.Z -m "release: vX.Y.Z"
     git push origin main
     git push origin vX.Y.Z
     ```

6. Build the gem
   - Run:
     ```bash
     gem build json_completer.gemspec
     ```
   - This should produce `json_completer-X.Y.Z.gem`.

7. Publish to RubyGems
   - Ask the maintainer for the current RubyGems MFA OTP code.
   - Run:
     ```bash
     gem push json_completer-X.Y.Z.gem --otp 123456
     ```
   - The maintainer provides the OTP code and you run the push command.

8. Verify the release
   - Check the latest published version:
     ```bash
     gem list -r ^json_completer$ --all
     ```
   - Optionally confirm on RubyGems.org that the version, README, and metadata look correct.

## Failure handling

- If validation fails, fix the issue before building or publishing.
- If `Gemfile.lock` still points at the old version, run `bundle install`, confirm the `PATH` section shows `json_completer (X.Y.Z)`, and recommit before tagging.
- If `gem build` fails, fix the gemspec or packaging issue and rebuild.
- If `gem push` fails because the version already exists, bump to a new version and repeat the release steps.
- If `gem push` fails due to auth, fix local RubyGems credentials and retry.
- If `gem push` fails due to an invalid or expired OTP, ask the maintainer for a fresh code and retry with `--otp`.

## Bad release handling

- Do not unpublish a stable gem version unless there is an exceptional legal or security reason.
- If a bad version is published, cut a new hotfix release and direct users to upgrade.
- If a version must be withdrawn, yank it from RubyGems:
  ```bash
  gem yank json_completer -v X.Y.Z
  ```

Use `gem yank` only when you explicitly decide the version must be withdrawn.
