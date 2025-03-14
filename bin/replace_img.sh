#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# replace an image with a new one

function Finish() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
    echo " pid $$ exited with rc=$rc"
  fi
  exit $rc
}

function ImagesInRun() {
  (
    cd ~tinderbox/run
    ls -d * 2>/dev/null
  )
}

function StopNonrespondingImages() {
  ImagesInRun |
    while read -r img; do
      if [[ ! -f ~tinderbox/run/$img/var/tmp/tb/EOL ]]; then
        if ! ts=$(stat -c %Z ~tinderbox/img/$img/var/tmp/tb/task.log 2>/dev/null); then
          if ! ts=$(stat -c %Z ~tinderbox/img/$img/var/tmp/tb/task 2>/dev/null); then
            if ! ts=$(getStartTime $img); then
              Finish 3
            fi
          fi
        fi
        hours=$(((EPOCHSECONDS - ts) / 3600))

        if [[ $hours -ge 24 ]]; then
          if __is_crashed $img; then
            echo -e "$(basename $0): image crashed $hours hours ago" >>~tinderbox/img/$img/var/tmp/tb/EOL
          elif __is_stopped $img; then
            echo -e "$(basename $0): image stopped $hours hours ago" >>~tinderbox/img/$img/var/tmp/tb/EOL
          elif __is_running $img; then
            echo -e "$(basename $0): last write was $hours hours ago" >>~tinderbox/img/$img/var/tmp/tb/EOL
            sudo $(dirname $0)/kill_img.sh $img
          fi
        fi
      fi
    done
}

function FreeSlotAvailable() {
  local running=$(wc -l < <(ImagesInRun))
  local replacing=$(pgrep -fc "/bin/bash /opt/tb/bin/replace")

  [[ $((running + replacing)) -le $desired_count ]]
}

function SetupANewImage() {
  echo
  date
  echo " call setup"
  local tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.$$.tmp)

  set +e
  # shellcheck disable=SC2024
  sudo $(dirname $0)/setup_img.sh -s &>$tmpfile
  set -e

  echo
  date
  if ! grep -A 30 '^ OK' $tmpfile; then
    tail -n 7 $tmpfile
  fi

  local img=$(grep -m 1 -Eo '  name: .*' $tmpfile | awk '{ print $2 }')
  mv $tmpfile ~tinderbox/img/$img/var/tmp/tb/$(basename $0).log
}

#######################################################################
set -eu # no -f
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "tinderbox" ]]; then
  echo " you must be tinderbox" >&2
  exit 1
fi

if [[ ! -d /run/tb ]]; then
  # just rebooted ?
  exit 2
fi

if [[ $# -eq 1 ]]; then
  desired_count=$1
else
  case $(nproc) in
  32) desired_count=12 ;;
  96) desired_count=16 ;;
  *) desired_count=$(($(nproc) / 3)) ;;
  esac
fi

# semaphore for the cleanup phase
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

source $(dirname $0)/lib.sh

StopNonrespondingImages

# free the slot(s)
while read -r img; do
  if __is_stopped $img; then
    rm ~tinderbox/run/$img
    if [[ -f ~tinderbox/logs/$img.log ]]; then
      mv ~tinderbox/logs/$img.log ~tinderbox/img/$img/var/tmp/tb
    fi
  fi
done < <(
  cd ~tinderbox/run
  ls */var/tmp/tb/EOL 2>/dev/null | cut -f 1 -d '/' -s
)

# end semaphore
rm $lockfile

if FreeSlotAvailable; then
  SetupANewImage
fi
