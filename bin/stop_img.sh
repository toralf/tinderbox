#!/bin/sh
#
#set -x

# stop tinderbox chroot image/s
#

for mnt in ${@:-~/amd64-*}
do
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

