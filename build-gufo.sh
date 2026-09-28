#!/usr/bin/env bash
# Rebuild the benchmark's pinned Gufo source with its reviewed ROCm 10 recipe.
set -Eeuo pipefail
gufo_commit=982bffea86fd5568759a420c4808c5b2123161c8
toolbox_commit=7d8e3f8a0bae0861c584a6c5d8113bc6eda23575
recipe_sha256=4373566977a53c6b6b266387539f894b8387f0b213e9474a0ebba88289734441
scratch_root=${TMPDIR:-/tmp/opencode}
mkdir -p "$scratch_root"
directory=$(mktemp -d "$scratch_root/gufo-share-build.XXXXXX")
trap 'rm -rf "$directory"' EXIT
curl --fail --location --silent --show-error \
    "https://raw.githubusercontent.com/kyuz0/amd-strix-halo-toolboxes/$toolbox_commit/toolboxes/Dockerfile.rocm-10.0-gufo" \
    --output "$directory/Dockerfile"
printf '%s  %s\n' "$recipe_sha256" "$directory/Dockerfile" | sha256sum --check
docker build --progress=plain \
    --build-arg GUFO_REPOSITORY=https://github.com/gufo-org/gufo.git \
    --build-arg "GUFO_COMMIT=$gufo_commit" \
    --tag gufo-local:982bffea-rocm10 "$directory"
docker run --rm --network none gufo-local:982bffea-rocm10 gufo --version
