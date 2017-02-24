#!/bin/sh
#
#set -x

# this script is called from job.sh before a new $task is processed
# to check for artefacts from the previous emerge step
#

# bug       pattern
#
# 563396    ./%\{_*
# 598840    /tmp/file??????

rc=0

# helper to prevent duplicate reports
#
findings=/tmp/$(basename $0).list
if [[ ! -f $findings ]]; then
  touch $findings
fi

for i in
do
  if [[ -e $i ]]; then
    grep -F -e "$i" -f $findings
    if [[ $? -eq 1 ]]; then
      ls -ld $i
      echo "$i" >> $findings
      rc=1
    fi
  fi
done

exit $rc
