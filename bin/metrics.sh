#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x


# use node_exporter's "textfile" feature to pump metrics into Prometheus


function printMetrics() {
  sum=0
  var="tinderbox_emerge_completed_img"
  echo -e "# HELP $var Total number of completed emerges of an image\n# TYPE $var gauge"
  for img in $(ls -d ~tinderbox/run/* 2>/dev/null)
  do
    n=$(grep -c -F -e '::: completed emerge' $img/var/log/emerge.log)
    (( sum+=n ))

    echo "$var{img=\"$(basename $img)\"} $n"
  done

  var="tinderbox_images_running"
  echo -e "# HELP $var Total number of running images\n# TYPE $var gauge"
  n=0
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

tmpfile=$(mktemp /tmp/metrics_XXXXXX.tmp)
echo "# $0   $(date -R)" > $tmpfile
printMetrics >> $tmpfile
chmod a+r $tmpfile
mv $tmpfile $datadir/tinderbox.prom
