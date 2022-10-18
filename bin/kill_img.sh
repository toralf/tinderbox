#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# kill running emerge process of an image and set it EOL


#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

for img in ${*?got no img}
do
  img=$(basename "$img")
  if [[ -d ~tinderbox/img/$img ]]; then
    echo "user decision at $(date)" >> ~tinderbox/img/$img/var/tmp/tb/EOL
    if ppid=$(pgrep -f "sudo.*bwrap.*$img"); then
      if pid=$(pstree -pa $ppid | grep -F 'emerge,' | grep -m1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
        pstree -UlnspuTa $pid
        echo
        kill -9 $pid
        echo
      else
        echo " $img: no pid found for $ppid"
      fi
    else
      echo " $img: no ppid found"
    fi
  else
    echo " $img: no image found"
  fi
done
