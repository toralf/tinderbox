#!/bin/bash
# set -x


function pruneNeeded()  {
  local fs=/dev/nvme0n1p4
  [[ -n $(df -m $fs | awk ' $1 == "'"$fs"'" && ($4 < 200000 || $5 > "89%")') ]]
}


#######################################################################
set -euf
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if pruneNeeded; then
  find ~tinderbox/distfiles/ -maxdepth 1 -ignore_readdir_race -type f -mtime +365                  -delete
  find ~tinderbox/distfiles/ -maxdepth 1 -ignore_readdir_race -type f -mtime +8   -name 'stage3-*' -delete

  find ~tinderbox/img/ -mindepth 1 -maxdepth 1 -type d -name '*-j*-20??????-??????' |\
  sort -t'-' -k 3,4 |\
  while read -r img
  do
    if pruneNeeded; then
      rm -r $img
      sleep 30    # lazy btrfs
    else
      break
    fi
  done
fi
