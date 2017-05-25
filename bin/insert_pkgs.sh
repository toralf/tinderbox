#!/bin/sh
#
#set -x

# pick up latest ebuilds from Git repository and put them on top of applicable package lists
#

mailto="tinderbox@zwiebeltoralf.de"

# collect all package list filenames if the image ...
#   1. is symlinked to ~
#   2. is running (no LOCK)
#   3. has a non-empty package list
#   4. doesn't have any special entries in its package list
#
applicable=""
for i in ~/run/*
do
  if [[ ! -e $i/tmp/LOCK ]]; then
    continue
  fi

  pks=$i/tmp/packages
  if [[ ! -s $pks ]]; then
    continue
  fi

  # do not change a package list if a special action is scheduled/not finished
  #
  grep -q -E "^(STOP|INFO|%|@|#)" $pks
  if [[ $? -eq 0 ]]; then
    continue
  fi

  # to achieve a higher coverage of the repository in a given time
  # do not test every image
  #
  if [[ $(($RANDOM % 3)) -eq 0 ]]; then
    continue
  fi

  applicable="$applicable $pks"
done

# holds the package names of added/changed/modified/renamed ebuilds
#
tmp=$(mktemp /tmp/pksXXXXXX)

# the host repository is synced every 3 hours via a cron job
# which ideally calls us afterwards;
# add 1 hour for the mirrors to be in sync with their masters
#
cd /usr/portage/
git diff --diff-filter=ACMR --name-status "@{ 4 hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' -e '/Manifest' | cut -f2- | xargs -n 1 | cut -f1-2 -d'/' | sort --unique > $tmp

info="# $(wc -l < $tmp) packages at $(date)"

# the output goes to the stdout of the caller (eg. email for a cron job)
#
echo "$info"
cat $tmp

if [[ -s $tmp ]]; then
  # append the packages onto applicable package list files
  #
  for pks in $applicable
  do
    echo "$info" >> $pks

    # shuffle packages around in a different way for each image
    # respect an upper limit of the amount of injected packages
    #
    sort --random-sort < $tmp | head -n 100 >> $pks
  done
fi

rm $tmp
