#!/bin/bash
# set -x


set -eu
export LANG=C.utf8

find ~/distfiles/ -maxdepth 1 -type f -atime +365 -exec rm "{}" \;

if [[ -n $(df -m | awk ' $1 == "/dev/nvme0n1p4" && $4 < 2000000 ') ]]; then
  img=$(ls -d ~/img/* 2>/dev/null | sort -t'-' -k 3,4 | head -n 1)
  if [[ -n $img && -d $img ]]; then
    echo "will clean up oldest image: $img"
    rm -rf $img
  fi
fi
