#!/bin/sh
#
#set -x

# start a tinderbox chroot image
#

orig=/tmp/tb/bin/runme.sh
copy=/tmp/runme.sh

for mnt in ${@:-~/amd64-*}
do
  # the image partition is not mounted
  #
  if [[ -L $mnt && ! -e $mnt ]]; then
    echo "broken symlink: $mnt"
    continue
  fi

  # image must not be locked
  #
  if [[ -f $mnt/tmp/LOCK ]]; then
    continue
  fi

  # non-empty package list required
  #
  pks=$mnt/tmp/packages
  if [[ -f $pks && ! -s $pks ]]; then
    echo " package list is empty for: $mnt"
    continue
  fi

  nohup nice sudo ~/tb/bin/chr.sh $mnt "cp $orig $copy && $copy" &

  sleep 1
done

# otherwise the prompt isn't shown due to 'nohup ... &'
#
sleep 1
