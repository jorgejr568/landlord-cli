#!/usr/bin/env bash
# Classify changes since a base SHA into release-gate areas so
# .github/workflows/test-pr.yaml can skip jobs whose inputs did not change.
# Source with RENTIVO_CI_AREAS_LIB_ONLY=1 to load the functions without
# dispatching.
set -euo pipefail

# Each pattern must cover every input of the jobs it gates. Changes under
# .github/ force every area to true because workflow and action edits can
# change any job's behavior.
BACKEND_PATH_PATTERN='^(backend/|uv\.lock$|pyproject\.toml$|scripts/[^/]+\.py$|scripts/tests/[^/]*\.py$)'
FRONTEND_PATH_PATTERN='^frontend/'
DOCKER_PATH_PATTERN='^(backend/Dockerfile|frontend/Dockerfile$|docker-compose[^/]*\.yml$|\.dockerignore$)'
SCRIPTS_PATH_PATTERN='^scripts/'
WORKFLOWS_PATH_PATTERN='^\.github/'

# Print area=true/false lines for changes between <base-sha> and HEAD.
# An unusable base (first push, tag push, force push) reports every area
# as true so the checks run rather than silently vanish.
changed_areas() {
  local base=${1:-}
  if [[ -z "$base" || "$base" =~ ^0+$ ]] || ! git cat-file -e "${base}^{commit}" 2>/dev/null; then
    printf 'backend=true\nfrontend=true\ndocker=true\nscripts=true\n'
    return 0
  fi
  local merge_base
  merge_base=$(git merge-base "$base" HEAD 2>/dev/null || printf '%s' "$base")
  # The file list is materialised before matching: piping `git diff` into
  # `grep -q` lets grep exit on its first match, killing `git diff` with
  # SIGPIPE, which `pipefail` would report as "nothing changed".
  local changed
  changed=$(git diff --name-only "$merge_base" HEAD)
  if grep -qE "$WORKFLOWS_PATH_PATTERN" <<<"$changed"; then
    printf 'backend=true\nfrontend=true\ndocker=true\nscripts=true\n'
    return 0
  fi
  local area pattern
  for area in backend frontend docker scripts; do
    case "$area" in
      backend) pattern="$BACKEND_PATH_PATTERN" ;;
      frontend) pattern="$FRONTEND_PATH_PATTERN" ;;
      docker) pattern="$DOCKER_PATH_PATTERN" ;;
      scripts) pattern="$SCRIPTS_PATH_PATTERN" ;;
    esac
    if grep -qE "$pattern" <<<"$changed"; then
      printf '%s=true\n' "$area"
    else
      printf '%s=false\n' "$area"
    fi
  done
}

if [[ -n "${RENTIVO_CI_AREAS_LIB_ONLY:-}" ]]; then
  return 0
fi

changed_areas "${1:-}"
