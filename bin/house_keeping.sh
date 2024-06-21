#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function olderThan() {
  local img=${1?IMG NOT SET}
  local days=${2?DAYS NOT SET}

  local start_time
  start_time=$(getStartTime $img)
  [[ $(((EPOCHSECONDS - start_time) / 86400)) -gt $days ]]
}

function lowSpace() {
  local maxperc=${1:-75} # max used space of whole FS in % (BTRFS is special!)

  local size avail
  read -r size avail < <(df -m /mnt/data --output=size,avail | tail -n 1)

  # value of available space in percent is often lower than 100-"percent value of df"
  local wanted
  wanted=$((size * (100 - maxperc) / 100)) # size is in MiB
  [[ $avail -lt $wanted ]]
}

function prepareDeletion() {
  local img=${1?IMG NOT SET}

  if [[ -f $img/var/tmp/tb/KEEP ]]; then
    # echo " $(date) marked to be kept: $img" >&2 # stdout is suppressed in cron job
    return 1
  fi

  if [[ -e ~tinderbox/run/$(basename $img) ]] || __is_running $img; then
    return 1
  fi

  # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
  if [[ -d $img/tmp/.private ]]; then
    chattr -R -a $img/tmp/.private
  fi
}

function pruneIt() {
  local img=${1?IMG NOT SET}
  local reason=${2:-no reason given}

  if ! prepareDeletion $img; then
    return 0
  fi

  echo " $(date) $reason : $img"
  rm -r -- $img
  sync
  sleep 20 # btrfs is lazy in reporting free space
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

source $(dirname $0)/lib.sh

# stage3 are released weekly, keep those from the last 2 weeks
latest=~tinderbox/distfiles/latest-stage3.txt
if gpg --verify $latest &>/dev/null; then
  find ~tinderbox/distfiles/ -maxdepth 1 -name 'stage3-amd64-*.tar.xz' -atime +15 |
    while read -r stage3; do
      if ! grep -q "/$(basename $stage3) " $latest; then
        rm -f $stage3{,.asc}
      fi
    done
fi

# mtime could be much older than even the host
find ~tinderbox/distfiles/ -ignore_readdir_race -maxdepth 1 -type f -atime +90 -delete

while read -r img; do
  if [[ ! -s $img/var/log/emerge.log && $((EPOCHSECONDS - $(stat -c %Z $img))) -gt 3600 ]]; then
    pruneIt $img "broken setup"
  fi
done < <(list_images_by_age "img")

while lowSpace && read -r img; do
  if olderThan $img 3; then
    if ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
      pruneIt $img "no issue"
    fi
  fi
done < <(list_images_by_age "img")

while lowSpace && read -r img; do
  if olderThan $img 7; then
    if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
      pruneIt $img "no bug reported"
    fi
  fi
done < <(list_images_by_age "img")

while lowSpace && read -r img; do
  if olderThan $img 14; then
    pruneIt $img "space needed"
  fi
done < <(list_images_by_age "img")

if lowSpace 89; then
  echo "Warning: fs nearly fullfilled" >&2
  exit 2
fi
