#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# set an image EOL, kill a running emerge process -or- the entrypoint script itself

set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root" >&2
  exit 1
fi

for img in ${*?got no image}; do
  img=$(basename "$img")
  if [[ -d ~tinderbox/img/$img ]]; then
    echo "user decision at $(date)" >>~tinderbox/img/$img/var/tmp/tb/EOL
    chmod g+w ~tinderbox/img/$img/var/tmp/tb/EOL
    chgrp tinderbox ~tinderbox/img/$img/var/tmp/tb/EOL
    if pid_bwrap=$(pgrep -f -u 0 -U 0 -G 0 " $(dirname $0)/bwrap.sh .*$(tr '+' '.' <<<$img)"); then
      if [[ -n $pid_bwrap && $(wc -l <<<$pid_bwrap) -eq 1 ]]; then
        if pid_emerge=$(pstree -pa $pid_bwrap | grep -F 'emerge,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
          if [[ -n $pid_emerge ]]; then
            pstree -UlnspuTa $pid_emerge | head -n 20 | cut -c1-200
            echo
            kill -9 $pid_emerge
          else
            echo " notice: empty emerge pid from $pid_bwrap"
            if pid_entrypoint=$(pstree -pa $pid_bwrap | grep -F 'entrypoint,' | grep -m 1 -Eo ',([[:digit:]]+) ' | tr -d ','); then
              if [[ -n $pid_entrypoint ]]; then
                pstree -UlnspuTa $pid_entrypoint | head -n 20 | cut -c1-200
                echo
                kill -15 $pid_entrypoint
                i=60
                while ((i--)) && kill -0 $pid_entrypoint; do
                  sleep 1
                done
                echo
                if kill -0 $pid_entrypoint; then
                  echo " notice: get roughly for $pid_entrypoint"
                  kill -9 $pid_entrypoint
                  echo
                fi
              else
                echo " notice: empty entrypoint pid from $pid_bwrap"
              fi
            else
              echo " notice: could not get entrypoint pid from $pid_bwrap"
            fi
          fi
        else
          echo " notice: could not get emerge pid from $pid_bwrap"
        fi
      else
        echo " notice: empty bwrap pid"
      fi
    else
      echo " info: could not get bwrap pid"
    fi
  else
    echo " error: $img: image not found" >&2
  fi
done
