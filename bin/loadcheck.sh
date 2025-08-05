#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

tmpdir=/tmp/$(basename $0).d

if [[ ! -d $tmpdir ]]; then
  mkdir $tmpdir
fi

max=${1:-$(($(nproc) * 5 / 3))}
while :; do
  load=$(cut -f 1 -d '.' /proc/loadavg)
  if [[ $load -gt $max ]]; then
    COLUMNS=10000 ps faux &>$tmpdir/ps-faux-$load-$(date +%Y%m%d-%H%M%S).txt
  fi
  sleep 15
done
