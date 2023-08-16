#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# replace an image with a new one

function Finish() {
  local rc=${1:-$?}
  local pid=$$

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
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

function ImagesInRunButEOL() {
  (
    set +f
    cd ~tinderbox/run
    ls */var/tmp/tb/EOL 2>/dev/null | cut -f 1 -d '/' -s
  )
}

function FreeSlotAvailable() {
  local r=$(ls /run/tinderbox | wc -l)
  local s=$(pgrep -c -f $(dirname $0)/setup_img.sh)

  [[ $((r + s)) -lt $desired_count && $(ImagesInRunShuffled | wc -l) -lt $desired_count ]]
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

lockfile="/tmp/$(basename $0).lck"
if [[ -s $lockfile ]]; then
  if kill -0 $(cat $lockfile) &>/dev/null; then
    exit 0
  fi
fi
echo $$ >"$lockfile"
trap Finish INT QUIT TERM EXIT

desired_count=${1:-13}
while :; do
  # if an image has stopped more than one day before then mark it as EOL
  while read -r oldimg; do
    if [[ ! -f ~tinderbox/run/$oldimg/var/tmp/tb/EOL ]] && ! __is_running $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 24 ]]; then
        echo -e "image stoppend, last task was $hours hours ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
      fi
    fi
  done < <(ImagesInRunShuffled)

  # if emerge runs for >2 days then replace the image
  while read -r oldimg; do
    if __is_running $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 49 ]]; then
        sudo $(dirname $0)/kill_img.sh $oldimg
      fi
    fi
  done < <(ImagesInRunShuffled)

  # free the slot
  while read -r oldimg; do
    if ! __is_running $oldimg; then
      rm ~tinderbox/run/$oldimg
      mv ~tinderbox/logs/$oldimg.log ~tinderbox/img/$oldimg/var/tmp/tb
    fi
  done < <(ImagesInRunButEOL)

  if FreeSlotAvailable; then
    if loadIsNotTooHigh; then
      echo
      date
      echo " setup a new image"
      tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
      sudo $(dirname $0)/setup_img.sh 2>&1 | tee $tmpfile >/dev/null
      img=$(grep "^  setup .* for .*$" $tmpfile | awk '{ print $4 }')
      echo
      date
      if [[ -e ~tinderbox/run/$img ]]; then
        echo " new $img"
        $(dirname $0)/start_img.sh $img
        cat $tmpfile | mail -s "INFO: setup new $img" ${MAILTO:-tinderbox}
      else
        echo " failed $img"
        cat $tmpfile | mail -s "NOTICE: setup failed for $img" ${MAILTO:-tinderbox}
        sleep $((3 * 3600))
      fi
      rm $tmpfile
    else
      sleep 60
    fi
    continue
  fi

  # loop as long as there're images marked as EOL
  while read -r oldimg; do
    if ! __is_running $oldimg; then
      continue 2
    fi
    sleep 60
  done < <(ImagesInRunButEOL)

  # if we reached this line then there's nothing (more) to do
  break
done

Finish 0
