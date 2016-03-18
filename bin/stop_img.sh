#!/bin/sh
#
#set -x

# send stop info to tinderbox chroot image
#

for mnt in ${@:-~/amd64-*}
do
  # chroot image must be running
  #
  if [[ -f $mnt/tmp/LOCK ]]; then
    # append a "STOP" line onto the package list file if there isn't already such a line
    #
    pks=$mnt/tmp/packages
    if [[ -s $pks ]]; then
      tail -n 1 $pks | grep -q "STOP" || echo "STOP" >> $pks
    fi
  fi
done

