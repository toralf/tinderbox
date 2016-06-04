#!/bin/sh
#
#set -x

# this script is called from job.sh before a new $task is processed
# to check for artefacts from the previous emerge step
#

# misplaced/left files
#
function checkTmp() {
  for f in /backend /usrlib64 /vz /no
  do
    if [[ -e $f ]]; then
      found=$(dirname $f)/.$(basename $f).found
      if [[ ! -f $found ]]; then
        ls -ld $f
        touch $found  # don't report this again
        rc=1
      fi
    fi
  done
}


# main
#

rc=0
checkTmp

exit $rc
