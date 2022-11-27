#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# set an image EOL, kill any running emerge process before


#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

for img in ${*?got no image}
do
  img=$(basename "$img")
  if [[ -d ~tinderbox/img/$img ]]; then
    echo "user decision at $(date)" >> ~tinderbox/img/$img/var/tmp/tb/EOL
    if b_pid=$(pgrep -f "sudo.*bwrap.*$img"); then
      if e_pid=$(pstree -pa $b_pid | grep -F 'emerge,' | grep -m1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
        pstree -UlnspuTa $e_pid | head -n 500
        echo
        kill -9 $e_pid
        echo
      fi
    fi
  else
    echo " error: $img: no image found"
  fi
done
