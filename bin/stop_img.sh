#!/bin/bash
#
# set -x


# stop tinderbox chroot image/s
#

set -euf
export LANG=C.utf8


if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you are not tinderbox "
  exit 1
fi

for i in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date +%X) "

  if [[ "$i" =~ ".." || "$i" =~ "//" || "$i" =~ [[:space:]] || "$i" =~ '\' ]]; then
    echo "illegal character(s) in parameter '$i'"
    continue
  fi

  mnt="$(ls -d ~tinderbox/img{1,2}/${i##*/} 2>/dev/null || true)"

  if [[ -z "$mnt" || ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 ]]; then
    echo "no valid mount point for: '$i'"
    continue
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
