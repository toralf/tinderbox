#!/bin/bash
# set -x


function pruneNeeded()  {
  local fs=/dev/nvme0n1p4
  [[ -n $(df -m $fs | awk ' $1 == "'"$fs"'" && ($4 < 200000 || $5 > "89%")') ]]
}


#######################################################################
set -eu
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi17.1-j3-20210612-103150

if pruneNeeded; then
  find ~tinderbox/distfiles/ -maxdepth 1 -type f -mtime +365                 -delete -ignore_readdir_race
  find ~tinderbox/distfiles/ -maxdepth 1 -type f -mtime +8   -name 'stage3*' -delete -ignore_readdir_race

  while pruneNeeded
  do
    find ~tinderbox/img/ -mindepth 1 -maxdepth 1 -type d -name '*-j*-20??????-??????' |\
    sort -t'-' -k 3,4 |\
    head -n 1 |\
    while read -r img
    do
      rm -r $img
      sleep 30    # lazy btrfs
    done
  done
fi
