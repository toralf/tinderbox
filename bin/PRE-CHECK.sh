#!/bin/sh
#
#set -x

# this script is called from job.sh before a new $task is processed
# to check for artefacts from the previous emerge step
#

rc=0

# misplaced/left files
#
for i in /tmp/conftest*
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
