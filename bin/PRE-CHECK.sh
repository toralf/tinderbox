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

#
exit 0

rc=0
for f in
do
  if [[ -e $f ]]; then
    reported=$(dirname $f)/.reported.$(basename $f)
    if [[ ! -f $reported ]]; then
      ls -ld $f
      touch $reported  # don't report this finding again
      rc=1
    fi
  fi
done

exit $rc
