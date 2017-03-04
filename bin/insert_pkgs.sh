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
available=""
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

  available="$available $pks"
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

# this goes to stdout of the caller
#
echo "$info"

if [[ -s $tmp ]]; then
  # prepend the package names onto available package list files
  #
  for pks in $available
  do
    # shuffle them around for each image in a different way before
    # limit max amount of packages, otherwise we might block that image forever
    #
    echo "$info"                            >> $pks
    sort --random-sort < $tmp | head -n 100 >> $pks
  done
fi

rm $tmp
