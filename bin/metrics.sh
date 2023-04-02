#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# use node_exporter's "textfile" feature to send metrics to Prometheus


function printMetrics() {
  local var="tinderbox_emerge_completed_img"
  echo -e "# HELP $var Total number of completed emerges of an image\n# TYPE $var gauge"
  for img in $(ls -d ~tinderbox/run/* 2>/dev/null)
  do
    local m=$(grep -c -F '::: completed emerge' $img/var/log/emerge.log 2>/dev/null)
    echo "$var{img=\"$(basename $img)\"} ${m:-0}"
  done

  var="tinderbox_images_running"
  echo -e "# HELP $var Total number of running images\n# TYPE $var gauge"
  local n=0
  for img in $(ls -d ~tinderbox/run/* 2>/dev/null)
  do
    if __is_running $img; then
      (( ++n ))
    fi
  done
  echo "$var $n"
}


#######################################################################
set -eu
export LANG=C.utf8
export PATH=/usr/sbin:/usr/bin:/sbin/:/bin

source $(dirname $0)/lib.sh

datadir=${1:-/var/lib/node_exporter} # default directory under Gentoo Linux
cd $datadir

tmpfile=$(mktemp /tmp/metrics_tinderbox_XXXXXX.tmp)
echo "# $0   $(date -R)" > $tmpfile
printMetrics >> $tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/tinderbox.prom
