#!/bin/bash
# Builds dist/<name>-<version>.zip and its sha256 for every package under packages/, or only the ones named.
# Used locally and by the release workflow.
# Usage: ./build.sh <version> [package...]
# Each package is a directory packages/<name>/ holding main.py and requirements.txt (plus the openapi.yaml and
# description.txt that build-fission-package.sh uses).
# Constraints: Targeted python:3.13-alpine (musl), so only pure-python requirements work: the build
# fails if anything compiled (*.so) ends up in an archive.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

VERSION=${1:?usage: build.sh <version> [package...], e.g. build.sh v0.1.0}
shift

if [ "$#" -gt 0 ]; then
  PACKAGES=("$@")
else
  PACKAGES=()
  for dir in packages/*/; do
    PACKAGES+=("$(basename "$dir")")
  done
fi
[ "${#PACKAGES[@]}" -gt 0 ] || { echo "no packages found under packages/" >&2; exit 1; }

rm -rf build dist
mkdir build dist

for NAME in "${PACKAGES[@]}"; do
  SRC="packages/$NAME"
  [ -f "$SRC/main.py" ] && [ -f "$SRC/requirements.txt" ] || { echo "$SRC must contain main.py and requirements.txt" >&2; exit 1; }

  BUILD="build/$NAME"
  ZIP="$NAME-$VERSION.zip"
  mkdir "$BUILD"

  python -m pip install --quiet --target "$BUILD" --only-binary=:all: -r "$SRC/requirements.txt"
  cp "$SRC/main.py" "$BUILD/"

  if find "$BUILD" -name '*.so' | grep -q .; then
    echo "compiled extensions found in $NAME - the python environment is musl/alpine, use pure-python requirements:" >&2
    find "$BUILD" -name '*.so' >&2
    exit 1
  fi

  find "$BUILD" -name __pycache__ -prune -exec rm -rf {} +
  (cd "$BUILD" && zip -X -q -r "../../dist/$ZIP" .)

  SHA256=$(shasum -a 256 "dist/$ZIP" | awk '{print $1}')
  echo "$SHA256  $ZIP" > "dist/$ZIP.sha256"

  echo "built dist/$ZIP"
  echo "sha256 $SHA256"
done
