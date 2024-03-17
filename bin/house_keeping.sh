#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function olderThan() {
  local img=${1?IMG NOT SET}
  local days=${2?DAYS NOT SET}

  local start_time
  if start_time=$(getStartTime $img); then
    [[ $(((EPOCHSECONDS - start_time) / 86400)) -gt $days ]]
  else
    return 1
  fi
}

function pruneNeeded() {
  local maxperc=${1:-75} # max used space of whole FS in % (BTRFS is special!)

  local size avail
  read -r size avail < <(df -m /mnt/data --output=size,avail | tail -n 1)

  # value of available space in percent is often lower than 100-"percent value of df"
  local wanted
  wanted=$((size * (100 - maxperc) / 100)) # size is in MiB
  [[ $avail -lt $wanted ]]
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
  rm -r $img
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
          rm -f $stage3{,.asc} # *.asc is 17. specific
        fi
      fi
    done
fi

# mtime value could be even older than the host itself
find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +90 -delete

while read -r img; do
  if [[ ! -s $img/var/log/emerge.log && $((EPOCHSECONDS - $(stat -c %Z $img))) -gt 7200 ]]; then
    pruneIt $img "broken unpack"
  fi
done < <(list_images_by_age "img")

while read -r img; do
  if olderThan $img 0 && [[ $(wc -l < <(qlop --merge --quiet --nocolor -f $img/var/log/emerge.log)) -lt 50 ]] && ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
    pruneIt $img "broken setup"
  fi
done < <(list_images_by_age "img")

while pruneNeeded && read -r img; do
  if olderThan $img 3; then
    if ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
      pruneIt $img "no issue"
    fi
  fi
done < <(list_images_by_age "img")

while pruneNeeded && read -r img; do
  if olderThan $img 7; then
    if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
      pruneIt $img "no bug reported"
    fi
  fi
done < <(list_images_by_age "img")

while pruneNeeded && read -r img; do
  if olderThan $img 14; then
    pruneIt $img "space needed"
  fi
done < <(list_images_by_age "img")

if pruneNeeded 89; then
  echo "Warning: fs nearly fullfilled" >&2
fi
