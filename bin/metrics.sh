#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# use node_exporter's "textfile" feature to send metrics to Prometheus

function printMetrics() {
  local var="tinderbox_emerge_completed_img"
  echo -e "# HELP $var Total number of completed emerges of images in ~/run\n# TYPE $var counter"
  while read -r img; do
    # shellcheck disable=SC2126
    local c=$(grep -F '::: completed emerge' ~tinderbox/run/$img/var/log/emerge.log 2>/dev/null | wc -l)
    if [[ $c -gt 0 ]]; then
      echo "$var{img=\"$img\"} $c"
    fi
  done < <(find ~tinderbox/run/ | xargs -n 1 basename)

  var="tinderbox_images"
  echo -e "# HELP $var Total number of running images\n# TYPE $var gauge"
  local r=0
  local i=0
  while read -r img; do
    if __is_running $img; then
      if [[ $img =~ "/run" ]]; then
        ((++r))
      else
        ((++i))
      fi
    fi
  done < <(list_images)
  echo "$var{state=\"run\"} $r"
  echo "$var{state=\"img\"} $i"
}

#######################################################################
set -euf
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
