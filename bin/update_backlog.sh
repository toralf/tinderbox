#!/bin/sh
#
# set -x

# pick up latest ebuilds from Git repository and put them on top of backlogs backlogs
#

mailto="tinderbox@zwiebeltoralf.de"

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# holds the package names of added/changed/modified/renamed ebuilds
#
acmr=/tmp/$(basename $0).acmr

# add 1 hour to let mirrors be in sync with master
#
cd /usr/portage/
git diff --diff-filter=ACMR --name-status "@{ ${1:-3} hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' -e '/Manifest' | cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s | sort --unique |\
grep -v -f ~/tb/data/IGNORE_PACKAGES > $acmr

if [[ -s $acmr ]]; then
  # shuffle packages around in a different manner for each image
  #
  for i in ~/run/*
  do
    sort --random-sort < $acmr >> $i/tmp/backlog.upd
  done
fi
