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
    # do not append a "STOP" line onto the package list file
    # that line is never reached if @preserved-rebuild or friends are in an endless loop
    #
    touch $mnt/tmp/STOP
  fi
done

