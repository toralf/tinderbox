#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# use node_exporter's "textfile" feature to send metrics to Prometheus

function printMetrics() {
  local var="tinderbox_emerge_completed_img"
  echo -e "# HELP $var Total number of completed emerges per image in ~/run\n# TYPE $var counter"
  # shellcheck disable=SC2038
  while read -r img; do
    if c=$(grep -cF '::: completed emerge' ~tinderbox/run/$img/var/log/emerge.log); then
      echo "$var{img=\"$img\"} $c"
    fi
  done < <(find ~tinderbox/run/ -type l | xargs -r -n 1 basename)

  var="tinderbox_images"
  echo -e "# HELP $var Total number of active images\n# TYPE $var gauge"
  local o=0
  local r=0
  local s=0
  local w=0
  while read -r img; do
    if __is_running $img; then
      if [[ $img =~ "/run" ]]; then
        if [[ $(cat $img/var/tmp/tb/task) =~ '# wait' ]]; then
          ((++w))
        else
          ((++r))
        fi
      else
        ((++o))
      fi
    else
      ((++s))
    fi
  done < <(list_images)
  echo "$var{state=\"other\"} $o"
  echo "$var{state=\"running\"} $r"
  echo "$var{state=\"stopped\"} $s"
  echo "$var{state=\"waiting\"} $w"
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

source $(dirname $0)/lib.sh

datadir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux
cd $datadir

tmpfile=$(mktemp /tmp/metrics_tinderbox_XXXXXX.tmp)
echo "# $0   $(date -R)" >$tmpfile
printMetrics >>$tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/tinderbox.prom
