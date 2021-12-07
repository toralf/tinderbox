#!/bin/bash
# set -x


function sortImagesByName()  {
  find ~tinderbox/img/ -mindepth 1 -maxdepth 1 -type d -name '*-j*-20??????-??????' |\
  sort -t'-' -k 3,4     # oldest first
}


function pruneNeeded()  {
  local fs=/dev/nvme0n1p4
  local x=200000          # free space in GB
  local y=89              # free space in percent
  [[ -n $(df -m $fs | awk ' $1 == "'"$fs"'" && ($4 < "'"$x"'" || $5 > "'"$y"'%")') ]]
}



function pruneDir() {
  local d=$1

  if [[ ! -d $d ]]; then
    return 1
  fi

  if ! __is_running $d; then
    # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
    if [[ -d $d/tmp/.private  ]]; then
      chattr -R -a $d/tmp/.private
    fi
    rm -r $d
    local rc=$?

    sleep 40    # lazy btrfs
    return $rc
  fi

  return 0
}


#######################################################################
set -euf
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

source $(dirname $0)/lib.sh

if pruneNeeded; then
  # prune distfiles older than 1 yr and stage3 files older than 1 week
  find ~tinderbox/distfiles/ -maxdepth 1 -ignore_readdir_race -type f -mtime +365                  -delete
  find ~tinderbox/distfiles/ -maxdepth 1 -ignore_readdir_race -type f -mtime +8   -name 'stage3-*' -delete

  # prune non-running images having no reported bug
  while read -r img && pruneNeeded
  do
    if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
      pruneDir $img
    fi
  done < <(sortImagesByName)

  # prune non-running images
  while read -r img && pruneNeeded
  do
    pruneDir $img
  done < <(sortImagesByName)
fi
