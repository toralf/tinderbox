#!/bin/sh
#
# set -x

# wrapper to allow us to change job.sh whilst a copy of it is in use
#
mailto="tinderbox@zwiebeltoralf.de"

# these are paths within a chroot image
#
orig=/tmp/tb/bin/job.sh
copy=/tmp/job.sh

rc=-1

while :;
do
  # 2 checks to avoid a race during copy operation
  #
  cp $orig $copy
  rc=$?
  if [[ $rc -ne 0 ]]; then
    break
  fi

  if [[ -s $copy ]]; then
    /bin/bash -n $copy
    rc=$?

    if [[ $rc -eq 0 ]]; then
      /bin/bash $copy
      rc=$?

      # rc=125: job.sh detected a newer version of
      #
      if [[ $rc -ne 125 ]]; then
        break
      fi
    fi
  fi
done

if [[ $rc -ne 0 ]]; then
  name=$(grep "^PORTAGE_ELOG_MAILFROM=" /etc/portage/make.conf | cut -f2 -d '"' | cut -f1 -d ' ')
  date | mail -s "$(date) $name rc=$rc" $mailto
fi

exit $rc
