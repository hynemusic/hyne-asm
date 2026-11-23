#!/usr/bin/env bash
# Re-records the expected values of spec/fixtures/*.json from the Swift reference implementation,
# then shows which fixture files changed. Run from any directory.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

HM_RECORD_FIXTURES=1 swift test --filter SharedFixtureTests
git diff --stat spec/fixtures
