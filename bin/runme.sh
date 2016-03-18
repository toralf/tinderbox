#!/bin/sh
#
# set -x

# wrapper to allow us to change job.sh whilst a copy of it is in use
#

# these are paths within a chroot image
#
orig=/tmp/tb/bin/job.sh
copy=/tmp/job.sh

while :;
do
  # 2 checks to avoid a race during copy operation
  #
  cp $orig $copy || exit $?
  if [[ -s $copy ]]; then
    /bin/bash -n $copy

    if [[ $? -eq 0 ]]; then
      /bin/bash $copy
      # rc=125: job.sh detected a newer version of itself
      #
      if [[ $? -eq 125 ]]; then
        continue
      fi
      break
    fi
  fi
done

exit $?