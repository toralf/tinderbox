#!/bin/sh
#
#set -x

# stop a tinderbox chroot image
#

# be verbose for dedicated image/s
#
verbose=0
if [[ $# -gt 0 ]]; then
  verbose=1
fi

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
    [[ $verbose -eq 1 ]] && echo " did NOT found LOCK: $mnt"
  fi
done

