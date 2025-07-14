#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function olderThan() {
  local img=${1?IMG NOT SET}
  local hours=${2?HOURS NOT SET}

  local start_time
  start_time=$(getStartTime $img)

  (((EPOCHSECONDS - start_time) / 3600 > hours))
}

# BTRFS is special: value of available space in percent is often lower than 100 - "percent value of df"
function lowSpace() {
  local maxperc=${1:-75} # max used space in %

  local size avail
  read -r size avail < <(df -m --sync --output=size,avail /mnt/data | tail -n 1)
  local wanted=$((size * (100 - maxperc) / 100))

  ((avail < wanted))
}

function finalCheck() {
  local img=${1?IMG NOT SET}

  if [[ -e ~tinderbox/run/$(basename $img) ]]; then
    return 1
  fi

  if [[ -f $img/var/tmp/tb/KEEP ]]; then
    return 1
  fi

  if __is_running $img; then
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

  if finalCheck $img; then
    echo " $(date) $reason : $img"
    rm -r -- $img
    sync
    sleep 30 # btrfs is lazy in reporting free space
  fi
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

lockfile="/tmp/$(basename $0).lock"
if [[ -s $lockfile ]]; then
  pid=$(cat $lockfile)
  if kill -0 $pid &>/dev/null; then
    exit 0
  else
    echo "ignore lock file, pid=$pid" >&2
  fi
fi
echo $$ >"$lockfile"

source $(dirname $0)/lib.sh

latest=~tinderbox/distfiles/latest-stage3.txt
if gpg --verify $latest &>/dev/null; then
  find ~tinderbox/distfiles/ -maxdepth 1 -name 'stage3-amd64-*.tar.*' |
    grep -v "\.asc$" |
    while read -r stage3; do
      if ! grep -q "/$(basename $stage3) " $latest; then
        rm -f $stage3{,.asc}
      fi
    done
else
  rm $latest
fi

# use atime, b/c mtime could be much older than the host itself
find ~tinderbox/distfiles/ -ignore_readdir_race -maxdepth 1 -type f -atime +90 -delete

while read -r img; do
  if [[ ! -s $img/var/log/emerge.log || $(wc -l <$img/var/log/emerge.log) -lt 300 ]] && olderThan $img 6; then
    pruneIt $img "broken setup"
  fi
done < <(list_images_by_age "img")

while lowSpace && read -r img; do
  if olderThan $img $((2 * 24)); then
    if ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
      pruneIt $img "no issue"
    fi
  fi
done < <(list_images_by_age "img")

while lowSpace && read -r img; do
  if olderThan $img $((9 * 24)); then
    if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
      pruneIt $img "no bug reported"
    fi
  fi
done < <(list_images_by_age "img")

while lowSpace && read -r img; do
  if olderThan $img $((14 * 24)); then
    pruneIt $img "free space is low"
  fi
done < <(list_images_by_age "img")

while lowSpace 89 && read -r img; do
  pruneIt $img "free space is very low"
done < <(list_images_by_age "img")

rm $lockfile

if lowSpace 95; then
  echo "Warning: fs nearly full" >&2
  exit 13
fi
