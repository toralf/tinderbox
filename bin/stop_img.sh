#!/bin/bash
#
# set -x

# stop tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " wrong user "
  exit 1
fi

for mnt in ${@:-$(ls ~/run 2>/dev/null)}
do
  echo -n "$(date) "

  # try to prepend ~/run if no path is given
  #
  if [[ ! -e $mnt && ! $mnt =~ '/' ]]; then
    mnt=~/run/$mnt
  fi

  if [[ ! -e $mnt ]]; then
    if [[ -L $mnt ]]; then
      echo "broken symlink: $mnt"
    else
      echo "vanished/invalid: $mnt"
    fi
    continue
  fi

  if [[ ! -d $mnt ]]; then
    echo "not a valid dir: $mnt"
    continue
  fi

  if [[ ! -f $mnt/var/tmp/tb/LOCK ]]; then
    echo " is not running: $mnt"
    continue
  fi

  if [[ -f $mnt/var/tmp/tb/STOP ]]; then
    echo " STOP marker already set: $mnt"
    continue
  fi

  echo " stopping     $mnt"
  touch $mnt/var/tmp/tb/STOP
done
