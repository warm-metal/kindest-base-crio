#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

SUDO=sudo
K8S_VERSION=v1.25.2
BASE_IMAGE=warmmetal/kindest-base-crio:latest

# install rsync
[ "$(command -v rsync)" != "" ] || ($SUDO apt-get update -y && $SUDO apt-get install rsync -y)
# install kind
[ "$(command -v kind)" != "" ] || (\
  $SUDO curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/v0.16.0/kind-linux-amd64 \
  && $SUDO chmod 0755 /usr/local/bin/kind)

# clone k8s
[ -d "$GOPATH"/src/k8s.io/kubernetes ] || (\
  mkdir -p "$GOPATH"/src/k8s.io/kubernetes \
  && git clone --depth 1 --branch ${K8S_VERSION} https://github.com/kubernetes/kubernetes.git "$GOPATH"/src/k8s.io/kubernetes)

# build
kind build node-image --base-image ${BASE_IMAGE}
