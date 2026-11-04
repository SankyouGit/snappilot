#!/usr/bin/env bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Annotation verification requires macOS with Xcode and XcodeGen." >&2
  exit 1
fi
repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_dir"
for required_tool in swift xcodegen xcodebuild; do
  if ! command -v "$required_tool" >/dev/null; then
    echo "Missing required tool: $required_tool" >&2
    exit 1
  fi
done

swift run snapverify
xcodegen generate
result_dir="$(mktemp -d "${TMPDIR:-/tmp}/snappilot-annotation-check.XXXXXX")"
build_args=(-project Snappilot.xcodeproj -scheme Snappilot -configuration Debug
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 'CODE_SIGN_IDENTITY=')
xcodebuild "${build_args[@]}" build
xcodebuild "${build_args[@]}" -resultBundlePath "$result_dir/AnnotationTests.xcresult" test
printf 'Native test results and render attachments: %s\n' "$result_dir/AnnotationTests.xcresult"
