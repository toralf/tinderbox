#!/bin/bash
# set -x

set -eu
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +365 -exec rm {} +

fs=/dev/nvme0n1p4
while [[ -n $(df -m $fs | awk ' $1 == "'"$fs"'" && ($4 < 200000 || $5 > "80%")') ]]
do
  img=$(ls -d ~tinderbox/img/*/ 2>/dev/null | sort -t'-' -k 3,4 | head -n 1)
  if [[ -d $img ]]; then
    rm -r $img
    sleep 30    # lazy btrfs
  else
    echo "nothing to delete ?!"
    exit 1
  fi
done
