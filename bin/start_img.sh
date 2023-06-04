#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# start tinderbox image/s

#############################################################################
#
# main
#
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

for i in ${@:-$(ls ~tinderbox/run 2>/dev/null)}; do
  echo -n "$(date +%X) "
  mnt=~tinderbox/img/$(basename $i)

  if [[ ! -d $mnt ]]; then
    echo "no valid mount point found for $mnt" >&2
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " has STOP file: $mnt/var/tmp/tb/STOP"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/EOL ]]; then
    echo " has EOL file: $mnt/var/tmp/tb/EOL"
    continue
  fi

  if [[ $(cat $mnt/var/tmp/tb/backlog{,,1st,.upd} /var/tmp/tb/task 2>/dev/null | wc -l) -eq 0 ]]; then
    echo " all backlogs are empty: $mnt"
    continue
  fi

  if __is_running "$mnt"; then
    echo " is running:  $mnt"
    continue
  fi

  echo " starting: $mnt"

  nice -n 3 sudo $(dirname $0)/bwrap.sh -m "$(basename $mnt)" -e "$(dirname $0)/job.sh" &>~tinderbox/logs/$(basename $mnt).log &
done

# avoid an invisible prompt
echo
