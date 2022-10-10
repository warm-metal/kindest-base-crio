#!/usr/bin/env bash
# Copyright 2020 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit -o nounset -o pipefail

# get the versions from the dockerfile
CNI_PLUGINS_VERSION="$(sed -n 's/ARG CNI_PLUGINS_VERSION="\(.*\)"/\1/p' Dockerfile)"
CRICTL_VERSION="$(sed -n 's/ARG CRICTL_VERSION="\(.*\)"/\1/p' Dockerfile)"
FUSE_OVERLAYFS_VERSION="$(sed -n 's/ARG FUSE_OVERLAYFS_VERSION="\(.*\)"/\1/p' Dockerfile)"
CRIO_VERSION="$(sed -n 's/ARG CRIO_VERSION="\(.*\)"/\1/p' Dockerfile)"

# darwin is great
SED="sed"
if which gsed &>/dev/null; then
  SED="gsed"
fi
if ! (${SED} --version 2>&1 | grep -q GNU); then
  echo "!!! GNU sed is required.  If on OS X, use 'brew install gnu-sed'." >&2
  exit 1
fi

# TODO: dry this out as well
ARCHITECTURES=(
    "amd64"
    "arm64"
)

echo
for ARCH in "${ARCHITECTURES[@]}"; do
    ARCH_URL=$ARCH
    [[ "$ARCH" == "amd64" ]] && ARCH_URL=x86_64
    [[ "$ARCH" == "arm64" ]] && ARCH_URL=aarch64
    FUSE_OVERLAYFS_TARBALL="fuse-overlayfs-${ARCH_URL}"
    FUSE_OVERLAYFS_URL="https://github.com/containers/fuse-overlayfs/releases/download/v${FUSE_OVERLAYFS_VERSION}/SHA256SUMS"
    SHASUM=$(curl -sSL --retry 5 "${FUSE_OVERLAYFS_URL}" | grep "${FUSE_OVERLAYFS_TARBALL}" | awk '{print $1}')
    ARCH_UPPER=$(echo "$ARCH" | tr '[:lower:]' '[:upper:]')
    echo "ARG FUSE_OVERLAYFS_${ARCH_UPPER}_SHA256SUM=${SHASUM}"
    $SED -i 's/ARG FUSE_OVERLAYFS_'"${ARCH_UPPER}"'_SHA256SUM=.*/ARG FUSE_OVERLAYFS_'"${ARCH_UPPER}"'_SHA256SUM="'"${SHASUM}"'"/' Dockerfile
done

echo
for ARCH in "${ARCHITECTURES[@]}"; do
    ARCH_URL=$ARCH
    CRIO_TARBALL="cri-o.${ARCH}.${CRIO_VERSION}.tar.gz"
    CRIO_URL="https://github.com/cri-o/cri-o/releases/download/${CRIO_VERSION}/${CRIO_TARBALL}.sha256sum"
    SHASUM=$(curl -sSL --retry 5 "${CRIO_URL}" | grep "${CRIO_TARBALL}" | awk '{print $1}')
    ARCH_UPPER=$(echo "$ARCH" | tr '[:lower:]' '[:upper:]')
    echo "ARG CRIO_${ARCH_UPPER}_SHA256SUM=${SHASUM}"
    $SED -i 's/ARG CRIO_'"${ARCH_UPPER}"'_SHA256SUM=.*/ARG CRIO_'"${ARCH_UPPER}"'_SHA256SUM="'"${SHASUM}"'"/' Dockerfile
done