#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function getCandidates() {
  local keepdays=${1?}

  ls -dt ~tinderbox/img/{17,23}.[0-9]*/ 2>/dev/null |
    tac |
    while read -r i; do
      if [[ -e ~tinderbox/run/$(basename $i) ]]; then
        continue
      fi

      if __is_running $i; then
        continue
      fi

      target=$i
      if [[ -s $i/var/log/emerge.log ]]; then
        target+=/var/log/emerge.log
      fi
      if [[ $(((EPOCHSECONDS - $(stat -c %Y $target)) / 86400)) -lt $keepdays ]]; then
        continue
      fi

      if [[ -f $i/var/tmp/tb/KEEP ]]; then
        continue
      fi

      echo $i
    done
}

function pruneNeeded() {
  local maxperc=${1?} # Use% value of the df command

  if read -r size avail < <(df -m /mnt/data --output=size,avail | tail -n 1); then
    local mb=$((size * (100 - maxperc) / 100)) # MB
    [[ $avail -lt $mb ]]
  else
    return 1
  fi
}

function pruneDir() {
  local d=$1
  local reason=${2:-""}

  # https://forums.gentoo.org/viewtopic-p-6072905.html?sid=461188c03d3c4d08de80136a49982d86#6072905
  if [[ -d $d/tmp/.private ]]; then
    chattr -R -a $d/tmp/.private
  fi

  echo " $(date) $reason : $d"
  rm -r $d
  local rc=$?
  sync

  return $rc
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

# always prune stage3 files
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

# always prune distfiles
find ~tinderbox/distfiles/ -maxdepth 1 -type f -atime +90 -delete

while read -r img && pruneNeeded 49; do
  if [[ ! -s $img/var/log/emerge.log || ! -d $img/var/tmp/tb ]]; then
    pruneDir $img "broken setup"
  fi
done < <(getCandidates 3)

while read -r img && pruneNeeded 59; do
  if ! ls $img/var/tmp/tb/issues/* &>/dev/null; then
    pruneDir $img "no issue"
  fi
done < <(getCandidates 3)

while read -r img && pruneNeeded 69; do
  if ! ls $img/var/tmp/tb/issues/*/.reported &>/dev/null; then
    pruneDir $img "no bug reported"
  fi
done < <(getCandidates 7)

while read -r img && pruneNeeded 89; do
  pruneDir $img "space needed"
done < <(getCandidates 14)

if pruneNeeded 95; then
  echo "Warning: fs nearly fullfilled" >&2
fi
