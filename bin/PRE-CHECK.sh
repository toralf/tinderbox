#!/bin/sh
#
#set -x

# this script is called from job.sh before a new $task is processed
# to check for artefacts from the previous emerge step
#

rc=0

# is resolv.conf symlinked to /var/run ?
# https://bugs.gentoo.org/show_bug.cgi?id=555694
#
if [[ -L /etc/resolv.conf ]]; then
  ls -l /etc/resolv.conf
  rm /etc/resolv.conf && cp /etc/resolv.conf.bak /etc/resolv.conf

  rc=1
fi

# misplaced/left files
#
for i in /%{__unitdir} /installed_by_webapp_eclass /tmp/nb-scan-cach /tmp/build.*.tmp.c*
do
  if [[ -e $i ]]; then
    found=$(dirname $i)/.$(basename $i).found
    if [[ ! -f $found ]]; then
      ls -ld $i
      touch $found
      rc=2
    fi
  fi
done

exit $rc
