module recorder {
  // Button presses begin asynchronous work. The microphone callbacks complete it.
  type RecorderState =
    | Idle
    | Acquiring
    | Recording
    | Paused
    | Releasing
    | Finished

  var state: RecorderState
  var micAcquired: bool

  // We listen only in Recording. Pausing retains the microphone without listening.
  val listening = state == Recording

  // The mic is not considered acquired while the acquisition request is pending.
  val micOwnershipIsConsistent =
    micAcquired == state.in(Set(Recording, Paused, Releasing))

  val listeningRequiresMic = not(listening) or micAcquired

  action init = all {
    state' = Idle,
    micAcquired' = false,
  }

  // The user asks to record. Acquisition has started, but the mic is not ours yet.
  action pressRecord = all {
    state == Idle,
    state' = Acquiring,
    micAcquired' = false,
  }

  // The asynchronous acquisition completes when audio listening actually begins.
  action startListening = all {
    state == Acquiring,
    state' = Recording,
    micAcquired' = true,
  }

  action pause = all {
    state == Recording,
    state' = Paused,
    micAcquired' = micAcquired,
  }

  action resume = all {
    state == Paused,
    state' = Recording,
    micAcquired' = micAcquired,
  }

  // Finishing starts an asynchronous release. The mic remains acquired meanwhile.
  action pressFinish = all {
    state.in(Set(Recording, Paused)),
    state' = Releasing,
    micAcquired' = true,
  }

  // The recorder is finished only after the release callback completes.
  action releaseMic = all {
    state == Releasing,
    state' = Finished,
    micAcquired' = false,
  }

  action step = any {
    pressRecord,
    startListening,
    pause,
    resume,
    pressFinish,
    releaseMic,
  }

  run acquisitionIsAsynchronousTest =
    init
      .then(pressRecord)
      .expect(state == Acquiring and not(micAcquired) and not(listening))

  run listeningAcquiresMicTest =
    init
      .then(pressRecord)
      .then(startListening)
      .expect(state == Recording and micAcquired and listening)

  run releaseIsAsynchronousTest =
    init
      .then(pressRecord)
      .then(startListening)
      .then(pressFinish)
      .expect(state == Releasing and micAcquired and not(listening))
      .then(releaseMic)
      .expect(state == Finished and not(micAcquired))

  run pauseRetainsMicTest =
    init
      .then(pressRecord)
      .then(startListening)
      .then(pause)
      .expect(state == Paused and micAcquired and not(listening))
      .then(resume)
      .expect(state == Recording and micAcquired and listening)

  run finishedIsTerminalTest =
    init
      .then(pressRecord)
      .then(startListening)
      .then(pressFinish)
      .then(releaseMic)
      .then(step.fail())
}
