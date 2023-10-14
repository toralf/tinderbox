#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# stop tinderbox image/s

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

for i in ${@:-$(list_active_images)}; do
  mnt=~tinderbox/img/$(basename $i)

  if [[ ! -d $mnt ]]; then
    echo " no valid mount point found for $mnt" >&2
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    continue
  fi

  if ! __is_locked "$mnt" && ! __is_cgrouped "$mnt"; then
    continue
  fi

  echo " $(date +%T) stopping $mnt"
  touch $mnt/var/tmp/tb/STOP
done
