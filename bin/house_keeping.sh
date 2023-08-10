#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function listImages() {
  ls -dt ~tinderbox/img/{17,23}.[0-9]*/ 2>/dev/null |
    tac
}

function olderThan() {
  local target=${1?}
  local days=${2?}

  [[ $(((EPOCHSECONDS - $(stat -c %Z $target)) / 86400)) -gt $days ]]
}

# available space is less than 100 - "% value of the df command"
function pruneNeeded() {
  local maxperc=${1?}

  if read -r size avail < <(df -m /mnt/data --output=size,avail | tail -n 1); then
    local mb=$((size * (100 - maxperc) / 100)) # MB
    [[ $avail -lt $mb ]]
  else
    return 1
  fi
}

function pruneIt() {
  local img=$1
  local reason=${2?}

  if [[ -f $img/var/tmp/tb/KEEP || -e ~tinderbox/run/$(basename $img) ]] || __is_running $img; then
    return 0
  fi

  # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
  if [[ -d $img/tmp/.private ]]; then
    chattr -R -a $img/tmp/.private
  fi

  echo " $(date) $reason : $img"
  if rm -r $img; then
    sync
  else
    return $?
  fi
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

# prune stage3 files
latest=~tinderbox/distfiles/latest-stage3.txt
if [[ -s $latest ]]; then
  find ~tinderbox/distfiles/ -name 'stage3-amd64-*.tar.xz' -mtime +15 |
    while read -r stage3; do
      if [[ $latest -nt $stage3 ]]; then
        if ! grep -q -F "/$(basename $stage3) " $latest; then
          rm -f $stage3{,.asc} # *.asc might not exist
        fi
      fi
    done
fi

# prune distfiles
find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +90 -delete

while read -r img; do
  if ! ls $img/var/tmp/tb/logs/dryrun*.log &>/dev/null; then
    if olderThan $img 1; then
      pruneIt $img "broken setup"
    fi
  fi
done < <(listImages)

# for higher coverage keep images for a while even if no bug was reported
while read -r img && pruneNeeded 89; do
  if ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
    if olderThan $img 7; then
      pruneIt $img "no issue"
    fi
  fi
done < <(listImages)
while read -r img && pruneNeeded 89; do
  if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
    if olderThan $img 14; then
      pruneIt $img "no bug reported"
    fi
  fi
done < <(listImages)

while read -r img && pruneNeeded 89; do
  if olderThan $img 21; then
    pruneIt $img "space needed"
  fi
done < <(listImages)

if pruneNeeded 93; then
  echo "Warning: fs nearly fullfilled" >&2
fi
