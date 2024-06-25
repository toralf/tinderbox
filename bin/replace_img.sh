#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# replace an image with a new one

function Finish() {
  local rc=$?
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
  local r=$(ls /run/tb | wc -l)
  local s=$(pgrep -c -f $(dirname $0)/setup_img.sh)
  [[ $((r + s)) -lt $desired_count && $(wc -l < <(ImagesInRunShuffled)) -lt $desired_count ]]
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

if [[ ! -d /run/tb ]]; then
  # just rebooted ?
  exit 1
fi

source $(dirname $0)/lib.sh

lockfile="/tmp/$(basename $0).lock"
if [[ -s $lockfile ]]; then
  pid=$(cat $lockfile)
  if kill -0 $pid &>/dev/null; then
    exit 0
  else
    echo "ignore lock file, pid=$pid" >&2
  fi
fi
echo $$ >"$lockfile"
trap Finish INT QUIT TERM EXIT

case $(nproc) in
32) desired_count=10 ;;
96) desired_count=16 ;;
*) desired_count=$(($(nproc) / 3)) ;;
esac

while :; do
  while read -r oldimg; do
    if [[ ! -f ~tinderbox/run/$oldimg/var/tmp/tb/EOL ]] && __is_stopped $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 24 ]]; then
        echo -e "image is not running and last task was $hours hours ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
      fi
    fi
  done < <(ImagesInRunShuffled)

  while read -r oldimg; do
    if [[ ! -f ~tinderbox/run/$oldimg/var/tmp/tb/EOL ]] && __is_crashed $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 24 ]]; then
        echo -e "image is crashed and last task was $hours hours ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
      fi
    fi
  done < <(ImagesInRunShuffled)

  while read -r oldimg; do
    if __is_running $oldimg; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600))
      if [[ $hours -ge 25 ]]; then
        echo -e "task runs longer than $hours hours" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
        sudo $(dirname $0)/kill_img.sh $oldimg
      fi
    fi
  done < <(ImagesInRunShuffled)

  # free the slot
  while read -r oldimg; do
    if __is_stopped $oldimg; then
      rm ~tinderbox/run/$oldimg
      mv ~tinderbox/logs/$oldimg.log ~tinderbox/img/$oldimg/var/tmp/tb
    fi
  done < <(ImagesInRunButEOL)

  if FreeSlotAvailable; then
    echo
    date
    echo " call setup"
    tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.$$.tmp) # intentionally not removed in case of an issue
    # shellcheck disable=SC2024
    if sudo $(dirname $0)/setup_img.sh -s &>$tmpfile; then
      img=$(awk '/ setup done for / { print $10 }' $tmpfile)
      mv $tmpfile ~tinderbox/img/$img/var/tmp/tb/$(basename $0).log
      date
      echo " $img"
    else
      rc=$?
      img=$(awk '/ setup failed for / { print $10 }' $tmpfile)
      date
      echo " $img failed rc=$rc"
      cat $tmpfile | mail -s "NOTICE: setup failed $img rc=$rc" ${MAILTO:-tinderbox@zwiebeltoralf.de}
      exit $rc
    fi
    continue
  fi

  while read -r oldimg; do
    if ! __is_running $oldimg; then
      continue 2
    fi
    sleep 60
  done < <(ImagesInRunButEOL)

  # reaching this line means that there's nothing more to do
  break
done

Finish
