#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# replace an image with a new one

function Finish() {
  local rc=${1:-$?}
  local pid=$$

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
    echo
    date
    echo " pid $pid exited with rc=$rc"
  fi

  rm $lockfile
  exit $rc
}

function ImagesInRunShuffled() {
  (
    set +f
    cd ~tinderbox/run
    ls -d * 2>/dev/null | shuf
  )
}

function ImagesInRunEOLShuffled() {
  (
    set +f
    cd ~tinderbox/run
    ls */var/tmp/tb/EOL 2>/dev/null | cut -f 1 -d '/' | shuf
  )
}

function FreeSlotAvailable() {
  local r=$(ls /run/tinderbox 2>/dev/null | wc -l)
  local s=$(pgrep -c -f $(dirname $0)/setup_img.sh)

  [[ $((r + s)) -lt $desired_count && $(ImagesInRunShuffled | wc -l) -lt $desired_count ]]
}

function load15IsNotGreaterThan() {
  local max=${1:-$(nproc)}

  while read -r value; do
    if [[ $value -gt $max ]]; then
      return 1
    fi
  done < <(
    # latest
    sar -q 1 1 | awk '/Average:/ { printf ("%.0f\n", $6) }'
    # average of current and previous hour
    sar -q -i 3600 24 | grep -B 2 "Average:" | grep -v -e 'ldavg-15' -e 'Average' | awk '{ printf ("%.0f\n", $7) }'
  )

  return 0
}

#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

lockfile="/tmp/$(basename $0).lck"
if [[ -s $lockfile ]]; then
  if kill -0 $(cat $lockfile) 2>/dev/null; then
    exit 1 # a previous instance is running
  fi
fi
echo $$ >"$lockfile"
trap Finish INT QUIT TERM EXIT

desired_count=${1:-11}
while :; do
  # if an image stopped for a day then mark it as EOL
  while read -r oldimg; do
    if [[ ! -f ~tinderbox/run/$oldimg/var/tmp/tb/EOL ]] && ! __is_running $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Y ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 24 ]]; then
        echo -e "image stoppend, last task is $hours hour/s ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
      fi
    fi
  done < <(ImagesInRunShuffled)

  # if an image hangs for >2 days then kill it
  while read -r oldimg; do
    if __is_running $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Y ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 49 ]]; then
        sudo $(dirname $0)/kill_img.sh $oldimg
      fi
    fi
  done < <(ImagesInRunShuffled)

  # free the slot
  while read -r oldimg; do
    if ! __is_running $oldimg; then
      rm ~tinderbox/run/$oldimg ~tinderbox/logs/$oldimg.log
    fi
  done < <(ImagesInRunEOLShuffled)

  if FreeSlotAvailable && load15IsNotGreaterThan 27; then
    echo
    date
    echo " + + + setup a new image + + +"
    sudo $(dirname $0)/setup_img.sh
    continue
  fi

  # loop as long as there're images marked as EOL
  while read -r oldimg; do
    if ! __is_running $oldimg; then
      continue 2
    fi
    sleep 60
  done < <(ImagesInRunEOLShuffled)

  break
done

Finish 0
