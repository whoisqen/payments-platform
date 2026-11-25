#!/usr/bin/env bash
# Copies the shared libraries a binary needs beyond distroless into an out tree, resolved to real paths.
set -euo pipefail

bin=${1:?binary}
out=${2:?out dir}
mkdir -p "$out"
skip='/(ld-linux[^/]*|libc|libm|libdl|libpthread|librt|libutil|libresolv|libgcc_s|libstdc\+\+)\.so'

deps=$(ldd "$bin")
# a library the build stage cannot resolve would be missing at runtime too; fail the build instead
if grep -q 'not found' <<<"$deps"; then
  echo "unresolved shared libraries of $bin:" >&2
  grep 'not found' <<<"$deps" >&2
  exit 1
fi

awk '/=> \//{print $3}' <<<"$deps" | while read -r lib; do
  if [[ $lib =~ $skip ]]; then continue; fi
  dir=$(dirname "$(readlink -f "$lib")")
  mkdir -p "$out$dir"
  cp -L "$lib" "$out$dir/$(basename "$lib")"
done
