#!/bin/sh
#
#set -x

# this script checks for artefacts from the last task
#

# bug       pattern
#
# 563396    ./%\{_*
# 598840    /tmp/file??????


# helper to prevent duplicate reports
#
findings=/tmp/$(basename $0).list
if [[ ! -f $findings ]]; then
  touch $findings
fi

rc=0

for i in
do
  if [[ -e $i ]]; then
    grep -F -e "$i" -f $findings
    if [[ $? -eq 1 ]]; then
      ls -ld $i                 # this output goes into our mail
      echo "$i" >> $findings
      rc=1
    fi
  fi
done

exit $rc
