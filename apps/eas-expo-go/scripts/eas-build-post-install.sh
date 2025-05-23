#!/usr/bin/env bash

set -xeuo pipefail

ROOT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/../../.. && pwd )"
export PATH="$ROOT_DIR/bin:$PATH"

if [ -n "${EXPO_TOKEN+x}" ]; then
  echo "Unsetting EXPO_TOKEN"
  unset EXPO_TOKEN
else
  echo "EXPO_TOKEN is not set"
fi

# Bail out if the versions endpoint is not available
et eas verify-versions-endpoint-available

if [ "$EAS_BUILD_PLATFORM" = "ios" ]; then
  et ios-generate-dynamic-macros
fi


if [ "$EAS_BUILD_PROFILE" = "versioned-client-add-sdk" ]; then
  if [ "$EAS_BUILD_PLATFORM" = "ios" ]; then
    pushd ios
    bundle install
    popd
  fi
  et add-sdk --platform $EAS_BUILD_PLATFORM
fi
