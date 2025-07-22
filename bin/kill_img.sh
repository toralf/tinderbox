#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# kill a running emerge process -or- the entrypoint script itself and set an image EOL

function killPid() {
  local pid=$1

  echo
  pstree -UlnspuTa $pid | tee ~tinderbox/img/$img/var/tmp/tb/killed_process.log | head -n 20 | cut -c 1-200
  if kill -0 $pid &>/dev/null; then
    kill -15 $pid
    # wait till TERM is propagated to all ppid's
    i=60
    echo -n "kill "
    while ((i--)) && kill -0 $pid &>/dev/null; do
      echo -n '.'
      sleep 1
    done
    echo
    if kill -0 $pid 2>/dev/null; then
      echo " notice: become roughly for $pid"
      kill -9 $pid
      echo
    fi
  fi

  # wait till cgroup is reaped
  echo -n "cgroup "
  while grep -q . /sys/fs/cgroup/tb/$img/cgroup.procs 2>/dev/null; do
    echo -n '.'
    sleep 1
  done
  echo
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

echo "$(basename $0) $(date)" >>~tinderbox/img/$img/var/tmp/tb/EOL
chmod g+w ~tinderbox/img/$img/var/tmp/tb/EOL
chgrp tinderbox ~tinderbox/img/$img/var/tmp/tb/EOL

if ! pid_bwrap=$(pgrep -f -u 0 -U 0 -G 0 " $(dirname $0)/bwrap.sh .*$(tr '+' '.' <<<$img)" | sort -nr | head -n 1); then
  echo " err: could not get bwrap pid $pid_bwrap" 2>&1
  exit 1
fi

if [[ -z $pid_bwrap ]]; then
  echo " err: empty bwrap pid $pid_bwrap" 2>&1
  exit 1
fi

if ! pid_emerge=$(
  set -o pipefail
  pstree -pa $pid_bwrap | grep 'emerge,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','
); then
  echo " err: could not get emerge pid of $pid_bwrap" 2>&1
  exit 1
fi

if [[ -n $pid_emerge ]]; then
  echo " kill emerge $pid_emerge"
  killPid $pid_emerge
else
  echo " notice: empty emerge pid from $pid_bwrap"
  if ! pid_entrypoint=$(
    set -o pipefail
    pstree -pa $pid_bwrap | grep 'entrypoint,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','
  ); then
    echo " err: could not get entrypoint pid of $pid_bwrap" 2>&1
    exit 1
  fi

  if [[ -z $pid_entrypoint ]]; then
    echo " err: empty entrypoint pid of $pid_bwrap" 2>&1
    exit 1
  fi

  echo " kill entrypoint $pid_entrypoint"
  killPid $pid_entrypoint
fi
