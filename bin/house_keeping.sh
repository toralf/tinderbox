#!/bin/bash
# set -x


function getCandidates()  {
  ls -d ~tinderbox/img/17.*-j*-20??????-?????? 2>/dev/null |\
  while read -r i
  do
    if [[ -e ~tinderbox/run/$(basename $i) ]]; then
      continue
    fi

    if __is_running $i; then
      continue
    fi

    if [[ $(( EPOCHSECONDS - $(stat -c %Y $i) )) -lt 86400 ]]; then
      continue
    fi

    echo $i
  done |\
  sort -t'-' -k 3,4
}


# $ df -m /dev/nvme0n1p4
# Filesystem     1M-blocks    Used Available Use% Mounted on
# /dev/nvme0n1p4   6800859 5989215    778178  89% /mnt/data
function pruneNeeded()  {
  local fs=/dev/nvme0n1p4
  local gb=200000          # wanted free space in GB
  local perc=89            # wanted free space in percent

  [[ -n $(df -m $fs | awk ' $1 == "'"$fs"'" && ($4 < "'"$gb"'" || $5 > "'"$perc"'%")') ]]
}



function pruneDir() {
  local d=$1

  if [[ ! -d $d ]]; then
    echo "$d is not a dir !"
    exit 1
  fi

  # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
  if [[ -d $d/tmp/.private  ]]; then
    chattr -R -a $d/tmp/.private
  fi
  rm -r $d
  local rc=$?

  sleep 40    # lazy btrfs
  return $rc
}


#######################################################################
set -euf
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

source $(dirname $0)/lib.sh

# prune distfiles not accessed within 1 yr and old stage3 files
if pruneNeeded; then
  find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +365 -delete

  latest=~tinderbox/distfiles/latest-stage3.txt
  if [[ -s $latest ]]; then
    find ~tinderbox/distfiles/ -maxdepth 1 -type f -name 'stage3-amd64-*.xz' |\
    while read -r stage3
    do
      if [[ $latest -nt $stage3 ]]; then
        if ! grep -q $(basename $stage3) $latest; then
          rm ${stage3} ${stage3}.DIGESTS.asc
        fi
      fi
    done
  fi
fi

# prune images with incompleted setup
while read -r img && pruneNeeded
do
  if [[ ! -f $img/var/log/emerge.log || ! -d $img/var/tmp/tb ]]; then
    pruneDir $img
  fi
done < <(getCandidates)

# prune images w/o any reported bug
while read -r img && pruneNeeded
do
  if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
    pruneDir $img
  fi
done < <(getCandidates)

# prune remaining images from oldest to newest
while read -r img && pruneNeeded
do
  pruneDir $img
done < <(getCandidates)
