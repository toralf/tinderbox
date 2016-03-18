#!/bin/sh
#
#set -x

# start a tinderbox chroot image
#

orig=/tmp/tb/bin/runme.sh
copy=/tmp/runme.sh

for mnt in ${@:-~/amd64-*}
do
  # an image
  #   - must not be locked
  #   - must have entries in its package list
  #
  if [[ ! -f $mnt/tmp/LOCK ]]; then
    pks=$mnt/tmp/packages
    if [[ ! -s $pks ]]; then
      echo " package list is empty for: $mnt"
      continue
    fi

    nohup nice sudo ~/tb/bin/chr.sh $mnt "cp $orig $copy && $copy" &
    sleep 1
  fi
done

# otherwise the prompt isn't shown due to 'nohup ... &'
#
sleep 1
