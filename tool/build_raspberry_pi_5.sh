#!/usr/bin/env bash
# Build a Linux ARM64 release bundle for Raspberry Pi 5 from a Linux x86_64 host.
#
# Usage:
#   tool/build_raspberry_pi_5.sh /path/to/raspberry-pi-os-sysroot
#
# The sysroot must be from the 64-bit Raspberry Pi OS installation on which the
# bundle will run. See README.md for an example of creating one.

set -euo pipefail

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="out/raspberry-pi-5"
sysroot="${1:-${RPI5_SYSROOT:-}}"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

[[ -n "$sysroot" ]] || fail 'provide the sysroot as the first argument or set RPI5_SYSROOT'
[[ -d "$sysroot" ]] || fail "sysroot does not exist: $sysroot"
sysroot="$(cd "$sysroot" && pwd)"
[[ -d "$sysroot/usr/include" ]] || fail "sysroot is missing usr/include: $sysroot"

for command in flutter clang cmake ninja pkg-config; do
  command -v "$command" >/dev/null || fail "required command not found: $command"
done

if [[ "$(uname -m)" != 'x86_64' ]]; then
  fail 'this cross-build script requires a Linux x86_64 host'
fi

pkgconfig_dirs=()
for directory in \
  "$sysroot/usr/lib/aarch64-linux-gnu/pkgconfig" \
  "$sysroot/usr/lib/pkgconfig" \
  "$sysroot/usr/share/pkgconfig"; do
  [[ -d "$directory" ]] && pkgconfig_dirs+=("$directory")
done
(( ${#pkgconfig_dirs[@]} > 0 )) || fail 'sysroot has no pkg-config directories for ARM64 libraries'

pkgconfig_libdir="$(IFS=:; printf '%s' "${pkgconfig_dirs[*]}")"
cd "$project_root"
mkdir -p "$build_dir"

# Flutter exposes build-dir as a global setting. Preserve it so this command
# does not change the location used by the developer's other projects.
previous_build_dir="$(flutter config --machine 2>/dev/null | sed -n 's/.*"build-dir"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

restore_flutter_config() {
  local exit_code=$?
  trap - EXIT
  set +e
  if [[ -n "$previous_build_dir" ]]; then
    flutter config --build-dir="$previous_build_dir" >/dev/null
  else
    flutter config --build-dir='' >/dev/null
  fi
  exit "$exit_code"
}
trap restore_flutter_config EXIT

printf 'Configuring Flutter output directory: %s\n' "$build_dir"
flutter config --build-dir="$build_dir" >/dev/null
printf 'Resolving Flutter dependencies...\n'
flutter pub get

# FindPkgConfig needs the target package metadata; otherwise CMake can mix the
# host GTK libraries with the ARM64 compiler target.
printf 'Building Linux ARM64 bundle (full log: %s/build.log)...\n' "$build_dir"
PKG_CONFIG_SYSROOT_DIR="$sysroot" \
PKG_CONFIG_LIBDIR="$pkgconfig_libdir" \
  flutter -v build linux --release \
    --target-platform=linux-arm64 \
    --target-sysroot="$sysroot" \
    --no-pub 2>&1 | tee "$build_dir/build.log"

printf '\nRaspberry Pi 5 bundle created below %s/%s/\n' "$project_root" "$build_dir"
find "$build_dir" -type f -name meshcore_open -printf '  %h\n' | sort -u
