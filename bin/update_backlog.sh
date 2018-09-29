#!/bin/sh
#
# set -x

# pick up latest changed ebuilds and merge them into backlog.upd
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# list of added/changed/modified/renamed ebuilds
#
acmr=/tmp/$(basename $0).acmr

cd /usr/portage/

# add 2 hours to let mirrors be in sync
#
git diff --diff-filter=ACMR --name-status "@{ ${1:-3} hour ago }".."@{ 2 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' | cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s | sort --unique |\
grep -v -f ~/tb/data/IGNORE_PACKAGES > $acmr

# add latest changes to each backlog.upd
#
if [[ -s $acmr ]]; then
  for i in $(ls ~/run 2>/dev/null)
  do
    # randomizing lowers probability of parallel build of the same package
    #
    bl=~/run/$i/tmp/backlog.upd
    sort --unique --random-sort $bl $acmr > $bl.tmp && cp $bl.tmp $bl && rm $bl.tmp
  done
fi
