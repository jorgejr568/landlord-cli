#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
source_contract="$repo_root/frontend/openapi.json"
android_contract="$repo_root/android/app/openapi.json"

case "${1:-sync}" in
  sync)
    cp "$source_contract" "$android_contract"
    ;;
  check)
    if ! cmp -s "$source_contract" "$android_contract"; then
      echo "android/app/openapi.json is stale; run make android-openapi-sync" >&2
      exit 1
    fi
    ;;
  *)
    echo "usage: $0 [sync|check]" >&2
    exit 64
    ;;
esac
