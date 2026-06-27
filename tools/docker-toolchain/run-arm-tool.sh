#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: run-arm-tool.sh <tool> [args...]" >&2
  exit 2
fi

tool="$1"
shift

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/../.." && pwd)"
image="${STM32_DOCKER_IMAGE:-generic-modbus-dev}"
docker_bin="${STM32_DOCKER_BIN:-docker}"
docker_cmd=("${docker_bin}")
container_tool="${tool}"
extra_mounts=()

if [[ "${STM32_DOCKER_USE_SUDO:-0}" == "1" ]]; then
  docker_cmd=(sudo -n "${docker_bin}")
fi

for vscode_dir in "${HOME}/.vscode" "${HOME}/.vscode-server"; do
  if [[ -d "${vscode_dir}" ]]; then
    extra_mounts+=(-v "${vscode_dir}:${vscode_dir}:ro")
  fi
done

if [[ "${tool}" == "arm-none-eabi-gdb" ]]; then
  container_tool="gdb-multiarch"
fi

exec "${docker_cmd[@]}" run --rm -i --network host \
  -v "${project_dir}:${project_dir}" \
  -v "${project_dir}:/workspace" \
  "${extra_mounts[@]}" \
  -w "${project_dir}" \
  "${image}" "${container_tool}" "$@"
