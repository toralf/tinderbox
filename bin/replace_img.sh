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
  exit $rc
}

function ImagesInRun() {
  (
    set +f
    cd ~tinderbox/run
    ls -d * 2>/dev/null
  )
}

function FreeSlotAvailable() {
  local i=$(wc -l < <(ImagesInRun))
  local l=$(ls /run/tb | wc -l) # depending when the USE flags are thrown during setup, an image is locked or not
  local r=$(pgrep -fc "/bin/bash /opt/tb/bin/replace")

  [[ $i -lt $desired_count && $l -lt $desired_count && $((l + r)) -le $desired_count ]]
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

if [[ $# -eq 1 ]]; then
  desired_count=$1
else
  case $(nproc) in
  32) desired_count=12 ;;
  96) desired_count=16 ;;
  *) desired_count=$(($(nproc) / 3)) ;;
  esac
fi

# chain the cleanup phase
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

# reap non-responding images
while read -r oldimg; do
  if [[ ! -f ~tinderbox/run/$oldimg/var/tmp/tb/EOL ]]; then
    if [[ -f ~tinderbox/img/$oldimg/var/tmp/tb/task.log ]]; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task.log)) / 3600)) 2>/dev/null
    elif [[ -f ~tinderbox/img/$oldimg/var/tmp/tb/task ]]; then
      hours=$(((EPOCHSECONDS - $(stat -c %Z ~tinderbox/img/$oldimg/var/tmp/tb/task)) / 3600)) 2>/dev/null
    else
      hours=$(((EPOCHSECONDS - $(getStartTime $oldimg)) / 3600))
    fi

    if [[ -n $hours && $hours -ge 24 ]]; then
      if __is_crashed $oldimg; then
        echo -e "$(basename $0): image crashed $hours hours ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
      elif __is_stopped $oldimg; then
        echo -e "$(basename $0): image stopped $hours hours ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
      elif __is_running $oldimg; then
        echo -e "$(basename $0): last log $hours hours ago" >>~tinderbox/img/$oldimg/var/tmp/tb/EOL
        sudo $(dirname $0)/kill_img.sh $oldimg
      fi
    fi
  fi
done < <(ImagesInRun)

# free the slot in ~/run
while read -r oldimg; do
  if __is_stopped $oldimg; then
    rm ~tinderbox/run/$oldimg
    mv ~tinderbox/logs/$oldimg.log ~tinderbox/img/$oldimg/var/tmp/tb
  fi
done < <(
  set +f
  cd ~tinderbox/run
  ls */var/tmp/tb/EOL 2>/dev/null | cut -f 1 -d '/' -s
)

# remove the chain around the cleanup
rm $lockfile

if FreeSlotAvailable; then
  echo
  date
  echo " call setup"
  tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.$$.tmp)
  set +e
  # shellcheck disable=SC2024
  sudo $(dirname $0)/setup_img.sh -s &>>$tmpfile
  rc=$?
  set -e
  date
  img=$(grep -m 1 -Eo '  name: .*' $tmpfile | awk '{ print $2 }')
  if [[ $rc -eq 0 ]]; then
    grep -A 10 -B 1 '^ OK' $tmpfile
    mv $tmpfile ~tinderbox/img/$img/var/tmp/tb/$(basename $0).log
  else
    echo "setup failed  $img  rc: $rc  tmpfile: $tmpfile"
  fi
else
  rc=0
fi

exit $rc
