#!/bin/bash
# For every package that build.sh built into dist/, renders dist/<name>-package.yaml (the Fission Package, Function and
# HTTPTrigger that point at the release asset) from .github/fission/package.yaml.tmpl, and renders
# packages/<name>/openapi.yaml to dist/<name>-openapi.yaml so it is published as a release asset too (the trigger's
# openapi annotation points at it). Each package's trigger description comes from packages/<name>/description.txt (one
# line, avoid the characters | & and backslash), and an optional packages/<name>/function-extras.yaml is added to the
# Function's spec. This is the Fission deployment layer on top of a plain build: it reads the
# zips and checksums that build.sh already wrote to dist/ and knows nothing about how they were made.
# Usage: GITHUB_REPOSITORY=owner/repo API_BASE_URL=https://api.example.com .github/scripts/build-fission-package.sh <version>
# (run after build.sh <version>; the workflow sets GITHUB_REPOSITORY itself and API_BASE_URL from release.yml). API_BASE_URL
# is the public host that serves the functions, which goes in each spec's servers block.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."

VERSION=${1:?usage: build-fission-package.sh <version>, e.g. build-fission-package.sh v0.1.0}
REPO=${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY, e.g. owner/repo}
API_BASE_URL=${API_BASE_URL:?set API_BASE_URL, the public base URL the functions are served from, e.g. https://api.example.com}
FISSION_NAMESPACE=${FISSION_NAMESPACE:-services}
FISSION_ENVIRONMENT=${FISSION_ENVIRONMENT:-python}

zips=(dist/*-"$VERSION".zip)
[ -f "${zips[0]}" ] || { echo "no dist/*-$VERSION.zip found, run build.sh $VERSION first" >&2; exit 1; }

for zip in "${zips[@]}"; do
  ZIP=$(basename "$zip")
  NAME=${ZIP%-"$VERSION".zip}
  SRC="packages/$NAME"
  [ -f "$SRC/openapi.yaml" ] && [ -f "$SRC/description.txt" ] || { echo "$SRC must contain openapi.yaml and description.txt" >&2; exit 1; }

  URL="https://github.com/$REPO/releases/download/$VERSION/$ZIP"
  OPENAPI_URL="https://github.com/$REPO/releases/download/$VERSION/$NAME-openapi.yaml"
  DESCRIPTION=$(head -n 1 "$SRC/description.txt")
  read -r SHA256 _ < "dist/$ZIP.sha256"

  sed -e "s|__NAME__|$NAME|g" \
      -e "s|__SERVER_URL__|$API_BASE_URL|g" \
      "$SRC/openapi.yaml" > "dist/$NAME-openapi.yaml"

  # packages/<name>/function-extras.yaml, if present, is spliced into the Function's spec (for example secrets:) at the
  # __FUNCTION_EXTRAS__ marker in the template; without it the marker line is just dropped
  if [ -f "$SRC/function-extras.yaml" ]; then
    EXTRAS=(-e "/__FUNCTION_EXTRAS__/{r $SRC/function-extras.yaml" -e "d" -e "}")
  else
    EXTRAS=(-e "/__FUNCTION_EXTRAS__/d")
  fi

  sed -e "s|__NAME__|$NAME|g" \
      -e "s|__NAMESPACE__|$FISSION_NAMESPACE|g" \
      -e "s|__ENVIRONMENT__|$FISSION_ENVIRONMENT|g" \
      -e "s|__URL__|$URL|g" \
      -e "s|__SHA256__|$SHA256|g" \
      -e "s|__OPENAPI_URL__|$OPENAPI_URL|g" \
      -e "s|__DESCRIPTION__|$DESCRIPTION|g" \
      "${EXTRAS[@]}" \
      .github/fission/package.yaml.tmpl > "dist/$NAME-package.yaml"

  echo "built dist/$NAME-package.yaml and dist/$NAME-openapi.yaml"
  echo "sha256 $SHA256"
  echo "url    $URL"
done
