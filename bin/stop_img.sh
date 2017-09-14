#!/bin/sh
#
# set -x

# stop tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " wrong user "
  exit 1
fi

for mnt in ${@:-$(ls ~/run)}
do
  if [[ ! -d $mnt ]]; then
    tmp=$(ls -d /home/tinderbox/{run,img?}/$mnt 2>/dev/null | head -n 1)
    if [[ ! -d $tmp ]]; then
      echo "cannot guess the full path to the image $mnt"
      continue
    fi
    mnt=$tmp
  fi

  # $mnt must not be a broken symlink
  #
  if [[ -L $mnt && ! -e $mnt ]]; then
    echo "broken symlink: $mnt"
    continue
  fi

  # $mnt must be or point to a directory
  #
  if [[ ! -d $mnt ]]; then
    echo "not a valid dir: $mnt"
    continue
  fi

  # chroot image must be running
  #
  if [[ ! -f $mnt/tmp/LOCK ]]; then
    echo " did NOT found LOCK: $mnt"
    continue
  fi

  # chroot image must not already be stopping
  #
  if [[ -f $mnt/tmp/STOP ]]; then
    echo " STOP marker already set: $mnt"
    continue
  fi

  echo " $(date) stopping $mnt"
  touch $mnt/tmp/STOP

done
