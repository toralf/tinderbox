#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# kill a running emerge process -or- the entrypoint script itself and set an image EOL

function killPid() {
  local pid=$1

  echo
  COLUMNS=10000 ps faux &>~tinderbox/img/$img/var/tmp/tb/ps-faux.log
  pstree -UlnspuTa $pid |
    tee -a ~tinderbox/img/$img/var/tmp/tb/EOL |
    head -n 40 |
    cut -c 1-140

  echo "$(basename $0): killing $pid" |
    tee -a ~tinderbox/img/$img/var/tmp/tb/EOL
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
  i=60
  while ((i--)) && grep -q . /sys/fs/cgroup/tb/$img/cgroup.procs 2>/dev/null; do
    echo -n '.'
    sleep 1
  done
  echo

  if grep -q . /sys/fs/cgroup/tb/$img/cgroup.proc 2>/dev/null; then
    return 1
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

echo "$(basename $0) $(date)" >>~tinderbox/img/$img/var/tmp/tb/EOL
chmod g+w ~tinderbox/img/$img/var/tmp/tb/EOL
chgrp tinderbox ~tinderbox/img/$img/var/tmp/tb/EOL

if ! pid_bwrap=$(
  set -o pipefail
  pgrep -f -u 0 -U 0 -G 0 " $(dirname $0)/bwrap.sh .*$(tr '+' '.' <<<$img)" | sort -nr | head -n 1
); then
  echo " err: could not get bwrap.sh pid of $img" 2>&1
  exit 1
fi

if pid_emerge=$(
  set -o pipefail
  pstree -pa $pid_bwrap | grep 'emerge,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','
); then
  echo " kill emerge $pid_emerge"
  killPid $pid_emerge

elif pid_setup=$(
  set -o pipefail
  pstree -pa $pid_bwrap | grep 'setup.sh,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','
); then
  echo " kill setup.sh $pid_setup"
  killPid $pid_setup

else
  echo " kill bwrap.sh $pid_bwrap"
  killPid $pid_bwrap
fi
