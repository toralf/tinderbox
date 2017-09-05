#!/bin/sh
#
#set -x

# purpose of this script is to check the pre-reqs
# # and/or for artefacts/issues of the previous task
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

if [[ -n "$(ls /var/db/pkg/sys-apps/dbus*/ 2>/dev/null)" && ! -f /etc/machine-id ]]; then
  echo "/etc/machine-id is missing"
  rc=1
fi

exit $rc
