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
FROM $BASE_IMAGE as base

FROM base as build-ons390x
ARG FUSE_OVERLAYFS_ARCH="s390x"

FROM base as build-onppc64le
ARG FUSE_OVERLAYFS_ARCH="ppc64le"

FROM base as build-onamd64
ARG FUSE_OVERLAYFS_ARCH="x86_64"

FROM base as build-onarm64
ARG FUSE_OVERLAYFS_ARCH="aarch64"

FROM build-on${TARGETARCH} as build

# copy in static files
# all scripts are 0755 (rwx r-x r-x)
COPY --chmod=0755 files/usr/local/bin/* /usr/local/bin/

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
      jq gnupg dbus make \
    && find /lib/systemd/system/sysinit.target.wants/ -name "systemd-tmpfiles-setup.service" -delete \
    && rm -f /lib/systemd/system/multi-user.target.wants/* \
    && rm -f /etc/systemd/system/*.wants/* \
    && rm -f /lib/systemd/system/local-fs.target.wants/* \
    && rm -f /lib/systemd/system/sockets.target.wants/*udev* \
    && rm -f /lib/systemd/system/sockets.target.wants/*initctl* \
    && rm -f /lib/systemd/system/basic.target.wants/* \
    && echo "ReadKMsg=no" >> /etc/systemd/journald.conf \
    && ln -s "$(which systemd)" /sbin/init

# We need a newer podman to work around the podman load bug #11619
RUN echo "Installing podman ..." \
    && mkdir -p /etc/apt/keyrings \
    && curl -fsSL https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_22.04/Release.key | gpg --dearmor | tee /etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg > /dev/null \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/devel_kubic_libcontainers_unstable.gpg] https://download.opensuse.org/repositories/devel:kubic:libcontainers:unstable/xUbuntu_22.04/ /" | tee /etc/apt/sources.list.d/devel:kubic:libcontainers:unstable.list > /dev/null \
    && DEBIAN_FRONTEND=noninteractive clean-install podman=4:4.5.1-0ubuntu22.04+obs78.3

ARG TARGETARCH
# Configure crictl binary from upstream
ARG CRICTL_VERSION="v1.25.1"
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

# Configure fuse-overlayfs binary from upstream
ARG FUSE_OVERLAYFS_VERSION="1.9"
ARG FUSE_OVERLAYFS_TARBALL="v${FUSE_OVERLAYFS_VERSION}/fuse-overlayfs-${FUSE_OVERLAYFS_ARCH}"
ARG FUSE_OVERLAYFS_URL="https://github.com/containers/fuse-overlayfs/releases/download/${FUSE_OVERLAYFS_TARBALL}"
ARG FUSE_OVERLAYFS_AMD64_SHA256SUM="3809625c3ecd9e13eb2fad709ddc6778944bbabe50ce1976b08085a035fea0aa"
ARG FUSE_OVERLAYFS_ARM64_SHA256SUM="a28fe7fdaeb5fbe8e7a109ff02b2abbae69301bb7e0446c855023edf58be51c3"
ARG FUSE_OVERLAYFS_PPC64LE_SHA256SUM="e9df32f9ae46d10e525e075fd1e6ba3284d179d030a5edb03b839791349eac60"
ARG FUSE_OVERLAYFS_S390X_SHA256SUM="693c70932df666b71397163a604853362e8316e734e7202fdf342b0f6096b874"

#Configure crio from upstream
ARG CRIO_VERSION="v1.20.9"
ARG CRIO_TARBALL="cri-o.${TARGETARCH}.${CRIO_VERSION}.tar.gz"
ARG CRIO_URL="https://github.com/cri-o/cri-o/releases/download/${CRIO_VERSION}/${CRIO_TARBALL}"
# ARG CRIO_AMD64_SHA256SUM="43f6e3a7ad6ae8cf05ed0f1e493578c28abf6a798aedb8ee9643ff7c25a68ca3"
# ARG CRIO_ARM64_SHA256SUM="d8040602e03c90e4482b4ce97b63c2cf1301cd2afb0aa722342f40f3537a1a1f"

RUN echo "Installing cri-o ..." \
    && curl -sSL --retry 5 --output /tmp/crio.${TARGETARCH}.tgz "${CRIO_URL}" \
    # && echo "${CRIO_AMD64_SHA256SUM}  /tmp/crio.amd64.tgz" | tee /tmp/crio.sha256 \
    # && echo "${CRIO_ARM64_SHA256SUM}  /tmp/crio.arm64.tgz" | tee -a /tmp/crio.sha256 \
    # && sha256sum --ignore-missing -c /tmp/crio.sha256 \
    # && rm -f /tmp/crio.sha256 \
    && tar -C /tmp -xzvf /tmp/crio.${TARGETARCH}.tgz \
    && (cd /tmp/cri-o && make install)\
    && rm -rf /tmp/cri-o /tmp/crio.${TARGETARCH}.tgz

RUN echo "Installing fuse-overlayfs ..." \
    && curl -sSL --retry 5 --output /tmp/fuse-overlayfs.${TARGETARCH} "${FUSE_OVERLAYFS_URL}" \
    && echo "${FUSE_OVERLAYFS_AMD64_SHA256SUM}  /tmp/fuse-overlayfs.amd64" | tee /tmp/fuse-overlayfs.sha256 \
    && echo "${FUSE_OVERLAYFS_ARM64_SHA256SUM}  /tmp/fuse-overlayfs.arm64" | tee -a /tmp/fuse-overlayfs.sha256 \
    && echo "${FUSE_OVERLAYFS_PPC64LE_SHA256SUM}  /tmp/fuse-overlayfs.ppc64le" | tee -a /tmp/fuse-overlayfs.sha256 \
    && echo "${FUSE_OVERLAYFS_S390X_SHA256SUM}  /tmp/fuse-overlayfs.s390x" | tee -a /tmp/fuse-overlayfs.sha256 \
    && sha256sum --ignore-missing -c /tmp/fuse-overlayfs.sha256 \
    && rm -f /tmp/fuse-overlayfs.sha256 \
    && mv -f /tmp/fuse-overlayfs.${TARGETARCH} /usr/local/bin/fuse-overlayfs \
    && chmod +x /usr/local/bin/fuse-overlayfs

# all configs are 0644 (rw- r-- r--)
COPY --chmod=0644 files/etc/* /etc/
# Keep containerd configuration to support kind build
COPY --chmod=0644 files/etc/containerd/* /etc/containerd/
COPY --chmod=0644 files/etc/cni/net.d/* /etc/cni/net.d/
COPY --chmod=0644 files/etc/crio/* /etc/crio/
COPY --chmod=0644 files/etc/default/* /etc/default/
COPY --chmod=0644 files/etc/sysctl.d/* /etc/sysctl.d/
COPY --chmod=0644 files/etc/systemd/system/* /etc/systemd/system/
COPY --chmod=0644 files/etc/systemd/system/kubelet.service.d/* /etc/systemd/system/kubelet.service.d/
COPY --chmod=0644 files/var/lib/kubelet/* /var/lib/kubelet/

RUN echo "Enabling crio and kubelet ... " \
    && systemctl enable crio \
    && systemctl enable kubelet.service

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
