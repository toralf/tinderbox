#!/bin/sh
#
#set -x

# stop tinderbox chroot image/s
#

for mnt in ${@:-~/amd64-*}
do
  # $mnt must not be a broken symlink
  #
  if [[ -L $mnt && ! -e $mnt ]]; then
    echo "broken symlink: $mnt"
    continue
  fi

  # $mnt must be a directory
  #
  if [[ ! -d $mnt ]]; then
    echo "not a valid dir: $mnt"
    continue
  fi

  # chroot image must be running
  #
  if [[ -f $mnt/tmp/LOCK ]]; then
    if [[ -f $mnt/tmp/STOP ]]; then
      echo " STOP marker already set: $mnt"
    else
      touch $mnt/tmp/STOP
    fi
  else
    echo " did NOT found LOCK: $mnt"
  fi
done

