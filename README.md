# Quint Connect for Swift

[![License](https://img.shields.io/badge/license-Apache%20License%202.0-blue)](LICENSE)

Model-based testing for Swift: replay the traces of a [Quint](https://quint-lang.org/) specification against your
Swift code and fail on the first step where the two disagree.

This is a Swift port of the design of Informal Systems'
[Quint Connect](https://github.com/informalsystems/quint-connect), which does the same for Rust.

## What it does

A Quint specification is a state machine. Quint can run it and write down the executions it explores as _traces_: for
each step, which action ran and what the state became. Quint Connect replays those traces against your implementation:

1. **Generate traces** with `quint run --mbt` (random simulation).
2. **Replay each step** by translating the Quint action into a call on your code, in a `Driver`.
3. **Compare state** after every step. Your driver projects its state into the specification's shape, and Quint Connect
   diffs it against the state Quint expected.

A divergence fails with the trace, the step, the action, and a diff of the two states, and the run prints the seed that
reproduces it.

## Quick start

Add the package, plus Quint (`npm install --save-dev @informalsystems/quint`):

```swift
.package(url: "https://github.com/LegacyCodeHQ/quint-connect-swift", from: "0.1.0")
```

Write a driver for your implementation:

```swift
import QuintConnect
import Testing

struct RecorderDriver: Driver {
    // The state to compare. Its fields are the specification's variables.
    struct Snapshot: Equatable, Sendable, Decodable {
        let state: String          // a nullary Quint variant decodes as its tag
        let micAcquired: Bool
    }

    var recorder = Recorder()

    mutating func step(_ step: Step) throws {
        switch step.actionTaken {
        case "init": recorder = Recorder()
        case "pressRecord": recorder.pressRecord()
        case "startListening": recorder.startListening()
        case "pressFinish": recorder.pressFinish()
        case "releaseMic": recorder.releaseMic()
        default: throw QuintConnectError.unhandledAction(step.actionTaken)
        }
    }

    func state() throws -> Snapshot {
        Snapshot(state: recorder.phase.rawValue, micAcquired: recorder.micAcquired)
    }
}

@Test func recorderMatchesItsSpecification() throws {
    try QuintConnect.simulate(RunConfig(spec: "Specifications/recorder.qnt", maxSamples: 100)) {
        RecorderDriver()
    }
}
```

If the implementation is wrong, for example it drops the mic when Finish is pressed instead of when release completes:

```
Specification and implementation diverge (trace 1, step 11, after `pressFinish`).
- specification
+ implementation
  ▿ RecorderDriver.Snapshot
    - state: "Releasing"
-   - micAcquired: true
+   - micAcquired: false
```

## Reading nondeterministic choices

Quint records the values an action chose with `nondet` in `step.nondetPicks`. Read them by name:

```swift
case "transfer":
    ledger.transfer(try step.pick("amount", as: Int.self), memo: try step.optionalPick("memo", as: String.self))
```

## How Quint values map to Swift

`ITFValue.decode(_:)` implements `Decodable` over Quint's trace format:

| Quint | Swift |
| --- | --- |
| `bool`, `int`, `str` | `Bool`, any integer type, `String` |
| `List`, tuple, `Set` | `[T]`, `Set<T>` |
| record | a `struct` |
| `Map` with `str` or `int` keys | `[String: V]`, `[Int: V]` |
| `Option` (`Some`, `None`) | `Optional` |
| sum-type variant without a payload | its tag as `String`, so a `String`-backed `enum` |
| sum-type variant with a payload | a record with `tag` and `value`; write an `init(from:)` |

A driver whose state is not worth checking can use `typealias State = Unchecked`.

## Choosing a trace source

| Source | API | Where it works |
| --- | --- | --- |
| Simulate with `quint run --mbt` | `QuintConnect.simulate(RunConfig(...))` | macOS, Linux |
| Traces already on disk | `QuintConnect.replay(directory:)` | everywhere, including iOS |
| One Quint `run` definition | `QuintConnect.replayTest(TestConfig(...))` | macOS, Linux; see the note below |

**iOS simulators cannot launch `quint`.** To test an iOS target, generate the traces before the test run and replay the
directory:

```sh
quint run spec.qnt --mbt --max-samples 100 --n-traces 100 --out-itf Traces/run_{seq}.itf.json --verbosity 0
```

```swift
try QuintConnect.replay(directory: Bundle(for: Self.self).url(forResource: "Traces", withExtension: nil)!) {
    MyDriver()
}
```

**`quint test` traces carry no action names** (Quint 0.33), unlike `quint run --mbt`. To replay a scripted `run`
definition, have the specification record its action in a sum-type variable and point the driver at it:

```swift
static var config: DriverConfig { DriverConfig(nondetPath: ["last"]) }
```

`Tests/QuintConnectTests/Fixtures/counter.qnt` shows the pattern.

## Configuration

| Setting | Where | Meaning |
| --- | --- | --- |
| `quint` | `RunConfig`, `TestConfig` | `.environment` (`$QUINT_PATH`, else `quint` on `PATH`) or `.path(url)` for a pinned install |
| `QUINT_SEED` | environment | reproduce a failure with the seed it printed |
| `QUINT_VERBOSE` | environment | `1` prints each step, `2` also prints raw states |
| `DriverConfig.statePath` | `Driver.config` | compare a nested part of the specification's state |

## Development

```sh
make setup        # install the pinned Quint (npm ci)
make test         # swift test, including conformance tests against real Quint
make check        # format-check + lint + test (the pre-push gate)
make setup-hooks  # activate .githooks/ for this clone
```

See [docs/porting-notes.md](docs/porting-notes.md) for how this maps to the Rust crate and what is not ported.

## License

Apache License 2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
