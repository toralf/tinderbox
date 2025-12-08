#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

function printMetrics() {
  local var="tinderbox_emerge_completed_img_total"
  echo -e "# HELP $var Total number of completed emerges per image in ~/run\n# TYPE $var counter"
  while read -r img; do
    if c=$(grep -cF '::: completed emerge' ~tinderbox/run/$img/var/log/emerge.log) 2>/dev/null; then
      echo "$var{img=\"$img\"} $c"
    fi
  done < <(find ~tinderbox/run/ -type l -print0 | xargs -r -n 1 --null basename)

  local var="tinderbox_age_img_total"
  echo -e "# HELP $var Age of an image in ~/run\n# TYPE $var counter"
  while read -r img; do
    if c=$((EPOCHSECONDS - $(getStartTime $img))) 2>/dev/null; then
      echo "$var{img=\"$img\"} $c"
    fi
  done < <(find ~tinderbox/run/ -type l -print0 | xargs -r -n 1 --null basename)

  var="tinderbox_images"
  echo -e "# HELP $var Total number of active images\n# TYPE $var gauge"
  local c=0
  local o=0
  local r=0
  local s=0
  while read -r img; do
    if [[ $img =~ "/run" ]]; then
      if __is_crashed $img; then
        ((++c))
      elif __is_running $img; then
        ((++r))
      else
        ((++s))
      fi
    else
      ((++o))
    fi
  done < <(list_active_images)
  echo "$var{state=\"crashed\"} $c"
  echo "$var{state=\"other\"} $o"
  echo "$var{state=\"running\"} $r"
  echo "$var{state=\"stopped\"} $s"
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

intervall=${1:-0}
datadir=${2:-/var/lib/node_exporter}

source $(dirname $0)/lib.sh

cd $datadir

lockfile="/tmp/tb-$(basename $0).lock"
if [[ -s $lockfile ]]; then
  pid=$(<$lockfile)
  if kill -0 $pid &>/dev/null; then
    exit 0
  else
    echo "ignore lock file, pid=$pid" >&2
  fi
fi
echo $$ >"$lockfile"

trap 'rm -f $lockfile' INT QUIT TERM EXIT

while :; do
  now=$EPOCHSECONDS

  # clean up old data if tinderbox is not running
  if ! pgrep -f $(dirname $0)/bwrap.sh 1>/dev/null; then
    truncate -s 0 $datadir/tinderbox.prom
  else
    tmpfile=$(mktemp /tmp/metrics_tinderbox_XXXXXX.tmp)
    echo "# $0   $(date -R)" >$tmpfile
    printMetrics >>$tmpfile
    chmod a+r $tmpfile
    mv $tmpfile $datadir/tinderbox.prom
  fi

  if [[ $intervall -eq 0 ]]; then
    break
  fi
  diff=$((EPOCHSECONDS - now))
  if [[ $diff -lt $intervall ]]; then
    sleep $((intervall - diff))
  fi
done
