#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# start tinderbox image/s

set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

for i in ${@:-$(ls ~tinderbox/run)}; do
  mnt=~tinderbox/img/$(basename $i)

  if [[ ! -d $mnt ]]; then
    echo " no valid mount point found for $mnt" >&2
    continue
  fi

  if [[ $(wc -l < <(cat $mnt/var/tmp/tb/backlog{,.1st,.upd} $mnt/var/tmp/tb/task 2>/dev/null)) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt" >&2
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/EOL ]]; then
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    if __is_stopped "$mnt"; then
      echo " unexpected STOP file for stopped image: $mnt" >&2
    fi
    continue
  fi

  if ! __is_stopped "$mnt"; then
    continue
  fi

  echo " $(date +%T) starting: $mnt"
  nice -n 3 sudo $(dirname $0)/bwrap.sh -m "$mnt" -e "$(dirname $0)/job.sh" &>~tinderbox/logs/$(basename $mnt).log &
done
