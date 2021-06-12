#!/bin/bash
# set -x


set -eu
export LANG=C.utf8

find ~/distfiles/ -maxdepth 1 -type f -atime +365 -exec rm "{}" \;

while [[ -n $(df -m | awk ' $1 == "/dev/nvme0n1p4" && $4 < 2000000 ') ]]
do
  img=$(ls -d ~/img/* 2>/dev/null | sort -t'-' -k 3,4 | head -n 1)
  if [[ -n $img && -d $img ]]; then
    echo
    date
    df -m /dev/nvme0n1p1
    echo "prune image: $img"
    rm -rf $img
    sleep 60              # lazy btrfs
    df -m /dev/nvme0n1p1
  fi
done
