#!/bin/bash
# set -x


function pruneNeeded()  {
  local fs=/dev/nvme0n1p4
  local x=200000          # free space in GB
  local y=89              # free space in percent
  [[ -n $(df -m $fs | awk ' $1 == "'"$fs"'" && ($4 < "'"$x"'" || $5 > "'"$y"'%")') ]]
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
      # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
      [[ -d $img/tmp/.private  ]] && chattr -R -a $img/tmp/.private
      rm -r $img
      sleep 30    # lazy btrfs
    else
      break
    fi
  done
fi
