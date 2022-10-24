#!/usr/bin/env bash

set -euxETo pipefail

#docker buildx create \
# --use \
# --name insecure-builder \
# --buildkitd-flags '--allow-insecure-entitlement security.insecure'
docker buildx use insecure-builder
docker buildx build --load --allow security.insecure --tag gentoo-build /run/gentoo/build
