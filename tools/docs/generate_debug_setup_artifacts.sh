#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
html="${project_dir}/docs/assets/debug-command-log.html"
png="${project_dir}/docs/assets/debug-command-log.png"

if [[ ! -f "${html}" ]]; then
  echo "Missing ${html}" >&2
  exit 1
fi

if node -e "require.resolve('playwright')" >/dev/null 2>&1; then
  node "${script_dir}/capture_debug_setup_doc.mjs" "${html}" "${png}"
elif command -v wkhtmltoimage >/dev/null 2>&1; then
  wkhtmltoimage --width 1280 "${html}" "${png}" >/dev/null
elif command -v convert >/dev/null 2>&1; then
  convert -background '#111318' -fill '#e6edf3' -font DejaVu-Sans-Mono -pointsize 18 "label:@${project_dir}/docs/assets/debug-command-log.txt" "${png}"
else
  echo "Need Playwright, wkhtmltoimage, or ImageMagick convert to render ${png}" >&2
  exit 1
fi

echo "Wrote ${png}"

