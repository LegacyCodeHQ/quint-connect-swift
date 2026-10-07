// A counter that records the action it took in `last`, so `quint test` traces carry action names.
// `quint run --mbt` records them itself, but `quint test` does not (Quint 0.33), so a spec that is replayed
// from its own `run` tests tracks the action in a sum-type variable and the driver points `nondetPath` at it.
module counter {
  type Action =
    | Init
    | Increment({ by: int })

  var total: int
  var last: Action

  action init = all {
    total' = 0,
    last' = Init,
  }

  action increment(by) = all {
    by > 0,
    total' = total + by,
    last' = Increment({ by: by }),
  }

  action step = {
    nondet by = 1.to(3).oneOf()
    increment(by)
  }

  run incrementTest =
    init.then(increment(2)).then(increment(3)).expect(total == 5)
}
