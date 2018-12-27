#!/bin/bash
#
# set -x

# pick up latest changed ebuilds and merge them into backlog.upd
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You must be the tinderbox user !"
  exit 1
fi

# list of package(s) to add
#
pks=/tmp/$(basename $0).txt

repo_path=$( portageq get_repo_path / gentoo ) || exit 2
cd $repo_path || exit 3

# add 2 hours to let mirrors be in sync
#
git diff --diff-filter=ACM --name-status "@{ ${1:-2} hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild'   |\
cut -f2- -s                         |\
xargs -n 1                          |\
cut -f1-2 -d'/' -s                  |\
sort --unique                       |\
grep -v -f ~/tb/data/IGNORE_PACKAGES > $pks

# add latest changes to each backlog.upd
#
if [[ -s $pks ]]; then
  for i in $(ls ~/run 2>/dev/null)
  do
    # shuffle around lowers the probability to build in parallel the same package
    #
    bl=~/run/$i/tmp/backlog.upd
    sort --unique --random-sort $bl $pks > $bl.tmp && cp $bl.tmp $bl && rm $bl.tmp
  done
fi
