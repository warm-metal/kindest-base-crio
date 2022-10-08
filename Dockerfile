# Copyright 2018 The Kubernetes Authors.
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

# kind node base image
#
# For systemd + docker configuration used below, see the following references:
# https://systemd.io/CONTAINER_INTERFACE/

# start from ubuntu, this image is reasonably small as a starting point
# for a kubernetes node image, it doesn't contain much we don't need
ARG BASE_IMAGE=ubuntu:22.04
FROM $BASE_IMAGE as build

# `docker buildx` automatically sets this arg value
ARG TARGETARCH

# amd64 => x86_64 ; arm64 => aarch64
ARG FUSE_OVERLAYFS_TARGETARCH

# Configure crictl binary from upstream
ARG CRICTL_VERSION="v1.25.0"
ARG CRICTL_URL="https://github.com/kubernetes-sigs/cri-tools/releases/download/${CRICTL_VERSION}/crictl-${CRICTL_VERSION}-linux-${TARGETARCH}.tar.gz"
ARG CRICTL_AMD64_SHA256SUM="86ab210c007f521ac4cdcbcf0ae3fb2e10923e65f16de83e0e1db191a07f0235"
ARG CRICTL_ARM64_SHA256SUM="651c939eca010bbf48cc3932516b194028af0893025f9e366127f5b50ad5c4f4"
ARG CRICTL_PPC64LE_SHA256SUM="1b77d1f198c67b2015104eee6fe7690465b8efa4675ea6b4b958c63d60a487e7"
ARG CRICTL_S390X_SHA256SUM="6b70ecaae209e196b2b0553e4c5e1b53240d002c88cb05cad442ddd8190d1481"

# Configure CNI binaries from upstream
ARG CNI_PLUGINS_VERSION="v1.1.1"
ARG CNI_PLUGINS_TARBALL="${CNI_PLUGINS_VERSION}/cni-plugins-linux-${TARGETARCH}-${CNI_PLUGINS_VERSION}.tgz"
ARG CNI_PLUGINS_URL="https://github.com/containernetworking/plugins/releases/download/${CNI_PLUGINS_TARBALL}"
ARG CNI_PLUGINS_AMD64_SHA256SUM="b275772da4026d2161bf8a8b41ed4786754c8a93ebfb6564006d5da7f23831e5"
ARG CNI_PLUGINS_ARM64_SHA256SUM="16484966a46b4692028ba32d16afd994e079dc2cc63fbc2191d7bfaf5e11f3dd"
ARG CNI_PLUGINS_PPC64LE_SHA256SUM="1551259fbfe861d942846bee028d5a85f492393e04bcd6609ac8aaa7a3d71431"
ARG CNI_PLUGINS_S390X_SHA256SUM="767c6b2f191a666522ab18c26aab07de68508a8c7a6d56625e476f35ba527c76"

# Configure fuse-overlayfs snapshotter binary from upstream
ARG FUSE_OVERLAYFS_VERSION="1.9"
ARG FUSE_OVERLAYFS_TARBALL="v${FUSE_OVERLAYFS_VERSION}/fuse-overlayfs-${FUSE_OVERLAYFS_TARGETARCH}"
ARG FUSE_OVERLAYFS_URL="https://github.com/containers/fuse-overlayfs/releases/download/${FUSE_OVERLAYFS_TARBALL}"
ARG FUSE_OVERLAYFS_AMD64_SHA256SUM="3809625c3ecd9e13eb2fad709ddc6778944bbabe50ce1976b08085a035fea0aa"
ARG FUSE_OVERLAYFS_ARM64_SHA256SUM="a28fe7fdaeb5fbe8e7a109ff02b2abbae69301bb7e0446c855023edf58be51c3"
ARG FUSE_OVERLAYFS_PPC64LE_SHA256SUM="e9df32f9ae46d10e525e075fd1e6ba3284d179d030a5edb03b839791349eac60"
ARG FUSE_OVERLAYFS_S390X_SHA256SUM="693c70932df666b71397163a604853362e8316e734e7202fdf342b0f6096b874"

# copy in static files
# all scripts are 0755 (rwx r-x r-x)
COPY --chmod=0755 files/usr/local/bin/* /usr/local/bin/

# all configs are 0644 (rw- r-- r--)
COPY --chmod=0644 files/etc/* /etc/
COPY --chmod=0644 files/etc/containerd/* /etc/containerd/
COPY --chmod=0644 files/etc/default/* /etc/default/
COPY --chmod=0644 files/etc/sysctl.d/* /etc/sysctl.d/
COPY --chmod=0644 files/etc/systemd/system/* /etc/systemd/system/
COPY --chmod=0644 files/etc/systemd/system/kubelet.service.d/* /etc/systemd/system/kubelet.service.d/

# Install dependencies, first from apt, then from release tarballs.
# NOTE: we use one RUN to minimize layers.
#
# First we must ensure that our util scripts are executable.
#
# The base image already has a basic userspace + apt but we need to install more packages.
# Packages installed are broken down into (each on a line):
# - packages needed to run services (systemd)
# - packages needed for kubernetes components
# - packages needed by the container runtime
# - misc packages kind uses itself
# - packages that provide semi-core kubernetes functionality
# After installing packages we cleanup by:
# - removing unwanted systemd services
# - disabling kmsg in journald (these log entries would be confusing)
#
# Then we install containerd from our nightly build infrastructure, as this
# build for multiple architectures and allows us to upgrade to patched releases
# more quickly.
#
# Next we download and extract crictl and CNI plugin binaries from upstream.
#
# Next we ensure the /etc/kubernetes/manifests directory exists. Normally
# a kubeadm debian / rpm package would ensure that this exists but we install
# freshly built binaries directly when we build the node image.
#
# Finally we adjust tempfiles cleanup to be 1 minute after "boot" instead of 15m
# This is plenty after we've done initial setup for a node, but before we are
# likely to try to export logs etc.

RUN echo "Installing Packages ..." \
    && DEBIAN_FRONTEND=noninteractive clean-install \
      systemd \
      conntrack iptables iproute2 ethtool socat util-linux mount ebtables kmod \
      libseccomp2 pigz \
      bash ca-certificates curl rsync \
      nfs-common fuse-overlayfs open-iscsi \
      jq \
    && find /lib/systemd/system/sysinit.target.wants/ -name "systemd-tmpfiles-setup.service" -delete \
    && rm -f /lib/systemd/system/multi-user.target.wants/* \
    && rm -f /etc/systemd/system/*.wants/* \
    && rm -f /lib/systemd/system/local-fs.target.wants/* \
    && rm -f /lib/systemd/system/sockets.target.wants/*udev* \
    && rm -f /lib/systemd/system/sockets.target.wants/*initctl* \
    && rm -f /lib/systemd/system/basic.target.wants/* \
    && echo "ReadKMsg=no" >> /etc/systemd/journald.conf \
    && ln -s "$(which systemd)" /sbin/init

RUN echo "Enabling kubelet ... " \
    && systemctl enable kubelet.service

ENV OS xUbuntu_22.04
ENV CRIO-VERSION v1.25.1
RUN echo "Installing cri-o ..." \
    && echo 'deb http://deb.debian.org/debian buster-backports main' > /etc/apt/sources.list.d/backports.list \
    && apt update -y \
    && apt install -y -t buster-backports libseccomp2 || apt update -y -t buster-backports libseccomp2 \
    && echo "deb [signed-by=/usr/share/keyrings/libcontainers-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable.list \
    && echo "deb [signed-by=/usr/share/keyrings/libcontainers-crio-archive-keyring.gpg] https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO-VERSION/$OS/ /" > /etc/apt/sources.list.d/devel:kubic:libcontainers:stable:cri-o:$CRIO-VERSION.list \
    && mkdir -p /usr/share/keyrings \
    && curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-archive-keyring.gpg \
    && curl -L https://download.opensuse.org/repositories/devel:/kubic:/libcontainers:/stable:/cri-o:/$CRIO-VERSION/$OS/Release.key | gpg --dearmor -o /usr/share/keyrings/libcontainers-crio-archive-keyring.gpg \
    && apt-get update -y \
    && apt-get install cri-o cri-o-runc -y \
    && systemctl enable crio \
    && rm -rf /var/lib/apt/lists/*

RUN echo "Installing crictl ..." \
    && curl -sSL --retry 5 --output /tmp/crictl.${TARGETARCH}.tgz "${CRICTL_URL}" \
    && echo "${CRICTL_AMD64_SHA256SUM}  /tmp/crictl.amd64.tgz" | tee /tmp/crictl.sha256 \
    && echo "${CRICTL_ARM64_SHA256SUM}  /tmp/crictl.arm64.tgz" | tee -a /tmp/crictl.sha256 \
    && echo "${CRICTL_PPC64LE_SHA256SUM}  /tmp/crictl.ppc64le.tgz" | tee -a /tmp/crictl.sha256 \
    && echo "${CRICTL_S390X_SHA256SUM}  /tmp/crictl.s390x.tgz" | tee -a /tmp/crictl.sha256 \
    && sha256sum --ignore-missing -c /tmp/crictl.sha256 \
    && rm -f /tmp/crictl.sha256 \
    && tar -C /usr/local/bin -xzvf /tmp/crictl.${TARGETARCH}.tgz \
    && rm -rf /tmp/crictl.${TARGETARCH}.tgz

RUN echo "Installing CNI plugin binaries ..." \
    && curl -sSL --retry 5 --output /tmp/cni.${TARGETARCH}.tgz "${CNI_PLUGINS_URL}" \
    && echo "${CNI_PLUGINS_AMD64_SHA256SUM}  /tmp/cni.amd64.tgz" | tee /tmp/cni.sha256 \
    && echo "${CNI_PLUGINS_ARM64_SHA256SUM}  /tmp/cni.arm64.tgz" | tee -a /tmp/cni.sha256 \
    && echo "${CNI_PLUGINS_PPC64LE_SHA256SUM}  /tmp/cni.ppc64le.tgz" | tee -a /tmp/cni.sha256 \
    && echo "${CNI_PLUGINS_S390X_SHA256SUM}  /tmp/cni.s390x.tgz" | tee -a /tmp/cni.sha256 \
    && sha256sum --ignore-missing -c /tmp/cni.sha256 \
    && rm -f /tmp/cni.sha256 \
    && mkdir -p /opt/cni/bin \
    && tar -C /opt/cni/bin -xzvf /tmp/cni.${TARGETARCH}.tgz \
    && rm -rf /tmp/cni.${TARGETARCH}.tgz \
    && find /opt/cni/bin -type f -not \( \
         -iname host-local \
         -o -iname ptp \
         -o -iname portmap \
         -o -iname loopback \
      \) \
      -delete

RUN echo "Installing fuse-overlayfs ..." \
    && curl -sSL --retry 5 --output /tmp/fuse-overlayfs.${TARGETARCH} "${FUSE_OVERLAYFS_URL}" \
    && echo "${FUSE_OVERLAYFS_AMD64_SHA256SUM}  /tmp/fuse-overlayfs.amd64" | tee /tmp/fuse-overlayfs.sha256 \
    && echo "${FUSE_OVERLAYFS_ARM64_SHA256SUM}  /tmp/fuse-overlayfs.arm64" | tee -a /tmp/fuse-overlayfs.sha256 \
    && echo "${FUSE_OVERLAYFS_PPC64LE_SHA256SUM}  /tmp/fuse-overlayfs.ppc64le" | tee -a /tmp/fuse-overlayfs.sha256 \
    && echo "${FUSE_OVERLAYFS_S390X_SHA256SUM}  /tmp/fuse-overlayfs.s390x" | tee -a /tmp/fuse-overlayfs.sha256 \
    && sha256sum --ignore-missing -c /tmp/fuse-overlayfs.sha256 \
    && rm -f /tmp/fuse-overlayfs.sha256 \
    && mv -f /tmp/fuse-overlayfs.${TARGETARCH} /usr/local/bin/fuse-overlayfs

RUN echo "Ensuring /etc/kubernetes/manifests" \
    && mkdir -p /etc/kubernetes/manifests

RUN echo "Adjusting systemd-tmpfiles timer" \
    && sed -i /usr/lib/systemd/system/systemd-tmpfiles-clean.timer -e 's#OnBootSec=.*#OnBootSec=1min#'

# squash
FROM scratch
COPY --from=build / /

# tell systemd that it is in docker (it will check for the container env)
# https://systemd.io/CONTAINER_INTERFACE/
ENV container docker
# systemd exits on SIGRTMIN+3, not SIGTERM (which re-executes it)
# https://bugzilla.redhat.com/show_bug.cgi?id=1201657
STOPSIGNAL SIGRTMIN+3
# NOTE: this is *only* for documentation, the entrypoint is overridden later
ENTRYPOINT [ "/usr/local/bin/entrypoint", "/sbin/init" ]
