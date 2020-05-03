#!/bin/bash
#
# set -x


# stop tinderbox chroot image/s
#

set -euf
export LANG=C.utf8


if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " wrong user "
  exit 1
fi

for i in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

  mnt="$(ls -d ~tinderbox/img{1,2}/${i##*/} 2>/dev/null || true)"

  if [[ ! -d "$mnt" ]]; then
    echo "not a valid mount point: '$mnt'"
    exit 1
  fi

  if [[ ! -f $mnt/var/tmp/tb/LOCK ]]; then
    echo " is not running: $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " is stopping: $mnt"
    continue
  fi

  echo " stopping     $mnt"
  touch "$mnt/var/tmp/tb/STOP"
done
