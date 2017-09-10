#!/bin/sh
#
#set -x

# pick up latest ebuilds from Git repository and put them on top of applicable package lists
#

mailto="tinderbox@zwiebeltoralf.de"

# collect all package list filenames if the image ...
#   1. is symlinked to ~/run
#   2. is running (LOCK and no STOP)
#   3. has a non-empty package list
#   4. doesn't have any special entries in its package list
#
applicable=""
for i in ~/run/*
do
  if [[ ! -f $i/tmp/LOCK ]]; then
    continue
  fi

  if [[ -f $i/tmp/STOP ]]; then
    continue
  fi

  backlog=$i/tmp/backlog
  if [[ ! -s $backlog ]]; then
    continue
  fi

  # do not change a package list if a special action is scheduled/not finished
  #
  grep -q -E "^(STOP|INFO|%|@|#)" $backlog
  if [[ $? -eq 0 ]]; then
    continue
  fi

  applicable="$applicable $backlog"
done

# holds the package names of added/changed/modified/renamed ebuilds
#
acmr=$(mktemp /tmp/acmrXXXXXX)

# give 1 hour to the mirrors to be in sync with the master
#
cd /usr/portage/
git diff --diff-filter=ACMR --name-status "@{ ${1:-3} hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' -e '/Manifest' | cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s | sort --unique > $acmr

info="# $(basename $0) at $(date): $(wc -l < $acmr) ACMR packages"

if [[ -s $acmr ]]; then
  # append the packages onto applicable package list files
  #
  for backlog in $applicable
  do
    echo "$info" >> $backlog

    # shuffle packages around in a different way for each image
    # and limit amount of injected packages per image
    #
    sort --random-sort < $acmr | head -n 100 >> $backlog
  done
fi

rm $acmr
