#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function olderThan() {
  local img=${1?}
  local days=${2?}

  local start_time
  if start_time=$(getStartTime $img); then
    [[ $(((EPOCHSECONDS - start_time) / 86400)) -gt $days ]]
  else
    return 1
  fi
}

function pruneNeeded() {
  local maxperc=${1:-75} # max used space of whole FS in % (BTRFS is special!)

  if read -r size avail < <(df -m /mnt/data --output=size,avail | tail -n 1); then
    # value of available space in percent is often lower than 100-"percent value of df"
    local wanted=$((size * (100 - maxperc) / 100)) # size is in MiB
    [[ $avail -lt $wanted ]]
  else
    return 1
  fi
}

function pruneIt() {
  local img=${1?}
  local reason=${2?}

  if [[ -f $img/var/tmp/tb/KEEP ]]; then
    echo " $(date) $reason but has to be kept: $img" >&2 # stdout is suppressed in cron job
    return 0
  fi

  if [[ -e ~tinderbox/run/$(basename $img) ]] || __is_running $img; then
    return 0
  fi

  # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
  if [[ -d $img/tmp/.private ]]; then
    chattr -R -a $img/tmp/.private
  fi

  echo " $(date) $reason : $img"
  if ! rm -r $img; then
    return 1
  fi
  sync
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

# stage3 are relased weekly, keep those from the week before too
latest=~tinderbox/distfiles/latest-stage3.txt
if [[ -s $latest ]]; then
  find ~tinderbox/distfiles/ -maxdepth 1 -name 'stage3-amd64-*.tar.xz' -atime +15 |
    while read -r stage3; do
      if [[ $latest -nt $stage3 ]]; then
        if ! grep -q "/$(basename $stage3) " $latest; then
          rm -f $stage3{,.asc} # *.asc might not exist
        fi
      fi
    done
fi

# mtime value can be older than the host itself, so use atime
find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +90 -delete

# kick off if less than X packages were emerged
while read -r img; do
  if olderThan $img 1; then
    if [[ ! -s $img/var/log/emerge.log || $(wc -l < <(qlop -mqC -f $img/var/log/emerge.log)) -lt 50 ]]; then
      pruneIt $img "broken setup"
    fi
  fi
done < <(list_images_by_age "img")

if ! pruneNeeded; then
  exit 0
fi

while read -r img && pruneNeeded; do
  if olderThan $img 3; then
    if ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
      pruneIt $img "no issue"
    fi
  fi
done < <(list_images_by_age "img")

while read -r img && pruneNeeded; do
  if olderThan $img 7; then
    if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
      pruneIt $img "no bug reported"
    fi
  fi
done < <(list_images_by_age "img")

while read -r img && pruneNeeded; do
  if olderThan $img 14; then
    pruneIt $img "space needed"
  fi
done < <(list_images_by_age "img")

if pruneNeeded 89; then
  echo "Warning: fs nearly fullfilled" >&2
fi
