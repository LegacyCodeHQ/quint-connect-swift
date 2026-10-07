.PHONY: setup warm-quint build test format format-check check setup-hooks

# Install the pinned Quint that the conformance tests run against.
setup:
	npm ci
	Scripts/install-quint-evaluator.sh
	$(MAKE) warm-quint

# Quint installs its evaluator on first use. Run it once here, so test processes that start together on a fresh
# machine (CI) do not race on the install. Scripts/install-quint-evaluator.sh has already put the binary in place
# from the public release URL, because Quint's own download goes through GitHub's API and hits its rate limit on CI.
warm-quint:
	node_modules/.bin/quint run Tests/QuintConnectTests/Fixtures/counter.qnt --max-samples 1 --max-steps 1 --verbosity 0

build:
	swift build

test:
	swift test

# Format in place, then lint.
format:
	xcrun swift-format format -i -r Sources Tests
	swiftlint lint --quiet --strict

# Change nothing; fail if a file is unformatted or breaks a rule.
format-check:
	xcrun swift-format lint --strict -r Sources Tests
	swiftlint lint --quiet --strict

# Everything the pre-push hook runs.
check: format-check test

# Activate the in-repo .githooks/ directory for this clone.
setup-hooks:
	git config core.hooksPath .githooks
