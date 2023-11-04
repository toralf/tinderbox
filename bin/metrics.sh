#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# use node_exporter's "textfile" feature to send metrics to Prometheus

function printMetrics() {
  local var="tinderbox_emerge_completed_img"
  echo -e "# HELP $var Total number of completed emerges per image in ~/run\n# TYPE $var counter"
  while read -r img; do
    if c=$(grep -cF '::: completed emerge' ~tinderbox/run/$img/var/log/emerge.log); then
      echo "$var{img=\"$img\"} $c"
    fi
  done < <(find ~tinderbox/run/ -type l -print0 | xargs -r -n 1 --null basename)

  local var="tinderbox_age_img"
  echo -e "# HELP $var Age of an image in ~/run\n# TYPE $var counter"
  while read -r img; do
    if c=$((EPOCHSECONDS - $(getStartTime $img))); then
      echo "$var{img=\"$img\"} $c"
    fi
  done < <(find ~tinderbox/run/ -type l -print0 | xargs -r -n 1 --null basename)

  var="tinderbox_images"
  echo -e "# HELP $var Total number of active images\n# TYPE $var gauge"
  local c=0
  local o=0
  local r=0
  local s=0
  local w=0
  while read -r img; do
    if [[ $img =~ "/run" ]]; then
      if __is_crashed $img; then
        ((++c))
      elif __is_running $img; then
        if [[ -f $img/var/tmp/tb/WAIT ]]; then
          ((++w))
        else
          ((++r))
        fi
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
  echo "$var{state=\"waiting\"} $w"

  var="tinderbox_cpu_frequency"
  echo -e "# HELP Current scaled cpu thread frequency in hertz.\n# TYPE $var gauge"
  grep "MHz" /proc/cpuinfo | awk '{ print NR-1, $4 }' | sed -e "s,^,$var{cpu=\"," -e 's, ,"} ,'
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

tmpfile=$(mktemp /tmp/metrics_tinderbox_XXXXXX.tmp)
trap 'rm $tmpfile' INT QUIT TERM EXIT

source $(dirname $0)/lib.sh

datadir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux
cd $datadir

echo "# $0   $(date -R)" >$tmpfile
printMetrics >>$tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/tinderbox.prom
