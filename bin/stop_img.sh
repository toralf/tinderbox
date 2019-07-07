#!/bin/bash
#
# set -x

# stop tinderbox chroot image/s
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " wrong user "
  exit 1
fi

if [[ $# -eq 0 ]]; then
  images=$(ls ~/run 2>/dev/null)
else
  images=""
  for mnt in ${@}
  do
    if [[ ! -d $mnt ]]; then
      i=$(ls -d ~/run/$mnt ~/img/$mnt ~/img?/$mnt 2>/dev/null | head -n 1)
      if [[ ! -d $mnt ]]; then
        echo "cannot guess the full path to the image $mnt"
        continue
      fi
    fi
    images="$images $mnt"
  done
fi

for mnt in $images
do
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
