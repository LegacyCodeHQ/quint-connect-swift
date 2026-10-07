#!/bin/sh
# Install the Rust evaluator that `quint run` and `quint test` need, without going through GitHub's API.
#
# Quint downloads the evaluator on first use through two unauthenticated calls to api.github.com. Those calls share
# GitHub's 60-requests-per-hour limit per IP address, which GitHub-hosted CI runners exhaust, so `make setup` fails
# there with "Failed to fetch from GitHub: rate limit exceeded". Quint skips the download entirely when
# $QUINT_HOME/rust-evaluator-<version>/quint_evaluator exists, so this puts the binary there from the public release
# URL, which is not rate limited the same way, with retries.
#
# It never fails the setup: if it cannot install the evaluator, Quint falls back to its own download.
set -u

cd "$(dirname "$0")/.."

quint_home="${QUINT_HOME:-$HOME/.quint}"

version=$(node -p "require('./node_modules/@informalsystems/quint/dist/src/rust/binaryManager').QUINT_EVALUATOR_VERSION" 2>/dev/null)
if [ -z "$version" ]; then
    echo "install-quint-evaluator: cannot read the evaluator version from the installed Quint; leaving it to Quint." >&2
    exit 0
fi

case "$(uname -s)/$(uname -m)" in
    Darwin/arm64) target=aarch64-apple-darwin ;;
    Darwin/x86_64) target=x86_64-apple-darwin ;;
    Linux/aarch64 | Linux/arm64) target=aarch64-unknown-linux-gnu ;;
    Linux/x86_64) target=x86_64-unknown-linux-gnu ;;
    *)
        echo "install-quint-evaluator: no prebuilt evaluator for $(uname -s)/$(uname -m); leaving it to Quint." >&2
        exit 0
        ;;
esac

final="$quint_home/rust-evaluator-$version"
if [ -x "$final/quint_evaluator" ]; then
    echo "install-quint-evaluator: $version already installed at $final"
    exit 0
fi

asset="quint_evaluator-$target.tar.gz"
url="https://github.com/quint-co/quint/releases/download/evaluator/$version/$asset"

mkdir -p "$quint_home" || exit 0
work=$(mktemp -d "$quint_home/.evaluator-XXXXXX") || exit 0

echo "install-quint-evaluator: downloading $url"
if curl -fsSL --retry 5 --retry-all-errors --retry-delay 3 -o "$work/$asset" "$url" &&
    tar -xzf "$work/$asset" -C "$work" &&
    [ -f "$work/quint_evaluator" ]; then
    chmod +x "$work/quint_evaluator"
    mkdir -p "$final"
    # A rename inside one filesystem is atomic, so a process that starts now never sees a partial binary.
    mv "$work/quint_evaluator" "$final/quint_evaluator"
    echo "install-quint-evaluator: installed $version at $final"
else
    echo "install-quint-evaluator: could not install $version; leaving it to Quint." >&2
fi

rm -rf "${work:?}"
exit 0
