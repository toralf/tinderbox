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
    touch $mnt/tmp/STOP
  else
    [[ $verbose -eq 1 ]] && echo " dit NOT found LOCK: $mnt"
  fi
done

