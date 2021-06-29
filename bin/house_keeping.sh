#!/bin/bash
# set -x


set -eu
export LANG=C.utf8


if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +365 -exec rm "{}" \;

# clean up if either >X% used or <Y GB are free
fs=/dev/nvme0n1p4
while [[ -n $(df -m | awk ' $1 == "'"$fs"'" && ($3/$2 > 0.85 || $4 < 200000)') ]]
do
  img=$(ls -d ~tinderbox/img/* 2>/dev/null | sort -t'-' -k 3,4 | head -n 1)
  if [[ -d $img ]]; then
    echo
    date
    df -m $fs
    echo "prune image: $img"
    rm -rf $img
    sleep 60              # lazy btrfs
    df -m $fs
  fi
done
