.PHONY: setup build test format format-check check setup-hooks

# Install the pinned Quint that the conformance tests run against.
setup:
	npm ci

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
