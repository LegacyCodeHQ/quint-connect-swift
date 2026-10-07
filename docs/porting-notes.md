# Porting notes: Quint Connect for Rust to Swift

The design follows [quint-connect](https://github.com/informalsystems/quint-connect) (v0.1.2). This records what maps
directly, what differs because Swift is not Rust, and what is not ported yet.

## Mapping

| Rust | Swift |
| --- | --- |
| `Driver` trait, `type State` | `Driver` protocol, `associatedtype State` |
| `State::from_driver`, `State::from_spec` | `Driver.state()`, `Driver.decode(specState:)` (defaults to `Decodable`) |
| `Config { state, nondet }` | `DriverConfig { statePath, nondetPath }` |
| `Step { action_taken, nondet_picks, state }` | `Step { actionTaken, nondetPicks, state }` |
| `switch!` macro | a `switch step.actionTaken` plus `step.pick(_:as:)` |
| `#[quint_run]` | `QuintConnect.simulate(RunConfig(...))` |
| `#[quint_test]` | `QuintConnect.replayTest(TestConfig(...))` |
| `itf` crate `Value` | `ITFValue` |
| `serde::Deserialize` | `Decodable`, via `ITFValue.decode(_:)` |
| `State = ()` | `State = Unchecked` |
| `QUINT_SEED`, `QUINT_VERBOSE` | read at run time, not compile time |

## Differences

- **No macros.** Swift macros would add a swift-syntax build dependency for little gain. A `switch` on the action name
  is idiomatic and the compiler checks exhaustiveness through the `default` case.
- **A fresh driver per trace.** The Rust crate reuses one driver and relies on the `init` step to reset it. Here every
  trace gets `makeDriver()`, so a driver bug in `init` cannot leak state from one trace into the next.
- **Trace replay is separate from trace generation.** `Process` does not exist on iOS, so loading and replaying ITF
  files (`QuintConnect.replay`) compiles everywhere, and generation is compiled only on macOS and Linux. This is what lets
  an iOS app replay traces that a `make` step generated beforehand.
- **Traces are replayed in natural file order** (`run_2` before `run_10`), so output is stable.
- **Sets and maps decode in a stable order** (sorted by their rendering), because ITF does not order them.

## Not ported

- **Windows** (`quint.cmd` handling). Swift on Windows is out of scope.
- **Compile-time macro diagnostics.** The Rust crate checks `switch!` patterns at build time. Here an unhandled
  action is a run-time `QuintConnectError.unhandledAction`.
- **Colored terminal logging.** Output is plain text on standard error.

## Findings against real Quint 0.32 and 0.33

- `quint run --mbt` in **0.32.0 labels the first state `step` instead of `init`** in traces that end early. 0.33.0
  labels it `init`. The package pins 0.33.0.
- `quint test` has no `--mbt` flag, and its ITF traces have no `mbt::actionTaken` or `mbt::nondetPicks`, in 0.32.0 and
  0.33.0. `replayTest` therefore needs a spec that records its action in a sum-type variable. Without one it fails with
  an error that says so.
