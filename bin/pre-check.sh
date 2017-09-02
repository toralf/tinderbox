#!/bin/sh
#
#set -x

# this script checks for artefacts/issues of the last task
#

rc=0

# findings=/tmp/$(basename $0).list
# if [[ ! -f $findings ]]; then
#   touch $findings
# fi
#
# for i in
# do
#   if [[ -e $i ]]; then
#     grep -e "^${i}$" $findings
#     if [[ $? -eq 1 ]]; then
#       ls -ld $i
#       echo "$i" >> $findings
#       rc=1
#     fi
#   fi
# done

if [[ "$task" =~ "dbus" &&  ! -f /etc/machine-id ]]; then
  echo "/etc/machine-id is missing"
  rc=1
fi

exit $rc
