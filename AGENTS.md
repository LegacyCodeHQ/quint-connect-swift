# AGENTS.md

Guidance for agents working in Quint Connect for Swift, a SwiftPM library that replays Quint specification traces
against Swift code (model-based testing). [`README.md`](README.md) is the user-facing entry point and
[`docs/porting-notes.md`](docs/porting-notes.md) records how it maps to the Rust crate it is ported from.

## Commands

```sh
make setup         # install the pinned Quint (npm ci); the conformance tests need it
make test          # swift test
make format        # swift-format in place, then SwiftLint
make format-check  # change nothing; fail on an unformatted file or a broken rule
make check         # format-check + test (the pre-push gate)
make setup-hooks   # activate .githooks/ for this clone
```

Single test: `swift test --filter ReplayTests`

The conformance suites (`RecorderConformanceTests`, `ScriptedScenarioTests`) run the real `quint` from `node_modules`
and are skipped, not failed, when `make setup` has not run. CI always runs `make setup` first.

## Hooks

`make setup-hooks` once per clone.

- **pre-commit** scans the staged diff with gitleaks, formats the staged Swift files and re-stages them, then
  strict-lints them. No build or tests.
- **pre-push** runs `make check`. `QUINT_CONNECT_SKIP_CHECKS=1` skips it for a WIP push; `git push --no-verify` skips
  every hook.

## Architecture

One library target, `QuintConnect`, in `Sources/QuintConnect/`:

| File | Role |
| --- | --- |
| `ITFValue.swift`, `ITFTrace.swift` | parse Quint's Informal Trace Format; pure, works on every platform |
| `ITFDecoder.swift` | `Decodable` over `ITFValue` |
| `Step.swift`, `Driver.swift`, `Replay.swift`, `Diff.swift` | the replay loop: derive a step, drive the code, compare state |
| `Quint.swift` | launches `quint` to generate traces; `#if os(macOS) \|\| os(Linux)` only, because `Process` is absent on iOS |

Keep everything except `Quint.swift` free of `Process` so the package still builds for iOS.

## Conventions

- swift-format owns layout, SwiftLint owns everything else; fix a violation, do not loosen `.swift-format` or
  `.swiftlint.yml`.
- Behavior that depends on Quint's output is pinned to the Quint in `package.json`. A Quint bump changes trace output:
  run `make test`, and update `docs/porting-notes.md` if a finding changes.
- Tests first: a failing test before the code, including for a fix found mid-task.
- `docs/porting-notes.md` lists what is deliberately not ported. Add to it when a difference from the Rust crate is
  chosen, not found.

## Licensing

Apache-2.0, because this ports the design of an Apache-2.0 project. Keep `LICENSE` and the attribution in `NOTICE`.

## Issue tracking

Tracked in `lever` under project **QCS**. Put the ticket in the commit scope: `type(QCS-1): subject`. Do not commit
unless asked.
