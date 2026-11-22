#!/usr/bin/env bash
# Copies the shared libraries a binary needs beyond distroless into an out tree, resolved to real paths.
set -euo pipefail

bin=${1:?binary}
out=${2:?out dir}
skip='/(ld-linux[^/]*|libc|libm|libdl|libpthread|librt|libutil|libresolv|libgcc_s|libstdc\+\+)\.so'

ldd "$bin" | awk '/=> \//{print $3}' | while read -r lib; do
  if [[ $lib =~ $skip ]]; then continue; fi
  dir=$(dirname "$(readlink -f "$lib")")
  mkdir -p "$out$dir"
  cp -L "$lib" "$out$dir/$(basename "$lib")"
done
