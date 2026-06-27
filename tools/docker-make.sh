#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
image="${STM32_DOCKER_IMAGE:-generic-modbus-dev}"
docker_bin="${STM32_DOCKER_BIN:-docker}"
docker_cmd=("${docker_bin}")

if [[ "${STM32_DOCKER_USE_SUDO:-0}" == "1" ]]; then
  docker_cmd=(sudo -n "${docker_bin}")
fi

exec "${docker_cmd[@]}" run --rm --privileged --network host \
  -v "${project_dir}:${project_dir}" \
  -v "${project_dir}:/workspace" \
  -w "${project_dir}" \
  "${image}" make "$@"
