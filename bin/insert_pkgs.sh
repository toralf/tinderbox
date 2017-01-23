#!/bin/sh
#
#set -x

# pick up latest ebuilds and put them on top of each applicable package list
#

mailto="tinderbox@zwiebeltoralf.de"

# collect all package list filenames if the image ...
#   1. is symlinked to ~
#   2. is running (no LOCK)
#   3. has a non-empty package list
#   4. doesn't have any special entries in its package list
#
avail_pks=""
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

  avail_pks="$avail_pks $pks"
done

# holds the package names of new/changed/modified/renamed ebuilds
#
tmp=$(mktemp /tmp/pksXXXXXX)

# the host repository is synced every 3 hours via a cron job
# which ideally calls us then too
# add 1 hour for the mirrors to be synced too
#
cd /usr/portage/
git diff --diff-filter=ACMR --name-status "@{ 4 hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' | cut -f2- | xargs -n 1 | cut -f1-2 -d'/' | sort --unique > $tmp

info="# $(wc -l < $tmp) packages at $(date)"
echo "$info"

if [[ -s $tmp ]]; then
  # prepend the package names onto change-able package list files
  #
  for pks in $avail_pks
  do
    # shuffle the packages around for each image in a different way
    #
    echo "$info"              >> $pks
    sort --random-sort < $tmp >> $pks

    # goes to stdout/the log file of the caller
    #
    echo "$pks"
  done
fi

rm $tmp
