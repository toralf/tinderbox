#!/bin/sh
#
# set -x

# purpose of this script is to check pre-reqs and left artefacts
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

# grep -q "^en_US ISO-8859-1" /etc/locale.gen
# if [[ $? -ne 0 ]]; then
#   if [[ ! -f /tmp/locale.gen.findings ]]; then
#     touch /tmp/locale.gen.findings
#     echo "found no locale"
#     cat /etc/locale.gen
#     rc=1
#   fi
# fi

exit $rc
