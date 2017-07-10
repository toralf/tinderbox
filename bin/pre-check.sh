#!/bin/sh
#
#set -x

# this script checks for artefacts left by the last task
#

# bug       pattern
#
# 623336    /tmp/tttest.*

exit 0

# helper to prevent duplicate reports
#
findings=/tmp/$(basename $0).list
if [[ ! -f $findings ]]; then
  touch $findings
fi

rc=0
for i in /tmp/tttest.*
do
  if [[ -e $i ]]; then
    grep -e "^${i}$" $findings
    if [[ $? -eq 1 ]]; then
      ls -ld $i
      echo "$i" >> $findings
      rc=1
    fi
  fi
done

exit $rc
