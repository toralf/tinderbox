#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# kill running emeerge of an image and set it EOL


#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

img=${1? img name is needed}
img=$(basename "$img")

if [[ -d ~tinderbox/img/$img ]]; then
  if ppid=$(pgrep -f "sudo.*bwrap.*$img"); then
    if pid=$(pstree -pa $ppid | grep -F 'emerge,' | grep -m1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
      kill -9 $pid
      echo "user decision, killed $pid of $ppid" >> ~tinderbox/img/$img/var/tmp/tb/EOL
      exit 0
    else
      echo " no pid for $ppid found"
    fi
  else
    echo " no ppid for $img found"
  fi
else
  echo " no image for $img found"
fi
exit 1
