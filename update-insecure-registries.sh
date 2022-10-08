#!/usr/bin/env bash

SED="sed"
if which gsed &>/dev/null; then
  SED="gsed"
fi
if ! (${SED} --version 2>&1 | grep -q GNU); then
  echo "!!! GNU sed is required.  If on OS X, use 'brew install gnu-sed'." >&2
  exit 1
fi

registries=$(printf '\\n"%s"' "$@")
$SED -i "s/insecure_registries = \[\]/insecure_registries = [$registries]/" files/etc/crio/crio.conf