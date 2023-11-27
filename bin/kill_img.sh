#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# kill a running emerge process -or- the entrypoint script itself and set an image EOL

function killPid() {
  local pid=$1

  pstree -UlnspuTa $pid | tee ~tinderbox/img/$img/var/tmp/tb/killed_process.log | head -n 20 | cut -c 1-200
  echo
  echo -n " stopping $pid "
  kill -15 $pid
  i=60
  while ((i--)) && kill -0 $pid 2>/dev/null; do
    echo -n '.'
    sleep 1
  done
  echo
  if kill -0 $pid 2>/dev/null; then
    echo " notice: get roughly for $pid"
    kill -9 $pid
    echo
  fi
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

[[ $# -eq 1 ]]

img=$(basename $1)

echo "user decision at $(date)" >>~tinderbox/img/$img/var/tmp/tb/EOL
chmod g+w ~tinderbox/img/$img/var/tmp/tb/EOL
chgrp tinderbox ~tinderbox/img/$img/var/tmp/tb/EOL

if pid_bwrap=$(pgrep -f -u 0 -U 0 -G 0 " $(dirname $0)/bwrap.sh .*$(tr '+' '.' <<<$img)"); then
  if [[ -n $pid_bwrap && $(wc -l <<<$pid_bwrap) -eq 1 ]]; then
    if pid_emerge=$(
      set -o pipefail
      pstree -pa $pid_bwrap | grep -F 'emerge,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','
    ); then
      if [[ -n $pid_emerge ]]; then
        echo " kill emerge"
        killPid $pid_emerge
      else
        echo " notice: empty emerge pid from $pid_bwrap"
        if pid_entrypoint=$(
          set -o pipefail
          pstree -pa $pid_bwrap | grep -F 'entrypoint,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','
        ); then
          if [[ -n $pid_entrypoint ]]; then
            echo " kill entrypoint"
            killPid $pid_entrypoint
          else
            echo " notice: empty entrypoint pid from $pid_bwrap"
          fi
        else
          echo " notice: could not get entrypoint pid from $pid_bwrap"
        fi
      fi
    else
      echo " notice: could not get emerge pid from $pid_bwrap"
    fi
  else
    echo " notice: empty or non-unique bwrap pid"
  fi
else
  echo " info: could not get bwrap pid"
fi
