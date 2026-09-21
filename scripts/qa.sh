#!/bin/zsh
set -euo pipefail

SCRIPT_DIR=${0:A:h}
PROJECT_DIR=${SCRIPT_DIR:h}
QA_DERIVED_DIR=${TMPDIR:-/private/tmp}/token-widgets-qa-derived

cd "$PROJECT_DIR"

command -v xcodegen >/dev/null || {
  print -u2 "xcodegen is required (brew install xcodegen)"
  exit 1
}

xcodegen generate --spec project.yml

xcodebuild -quiet \
  -project TokenWidgets.xcodeproj \
  -scheme TokenWidgetsApp \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath "$QA_DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  test

xcodebuild -quiet \
  -project TokenWidgets.xcodeproj \
  -scheme TokenWidgetsApp \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "$QA_DERIVED_DIR" \
  CODE_SIGNING_ALLOWED=NO \
  analyze

print "QA passed: unit tests and Release static analysis"
