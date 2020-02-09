#!/bin/bash
#
# set -x

# pick up latest changed packages and merge them into backlog.upd
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You are not tinderbox !"
  exit 1
fi

repo_path=$(portageq get_repo_path / gentoo) || exit 2
cd $repo_path || exit 3

# hold updated package(s) here
#
pks=/tmp/${0##*/}.txt

# if called hourly then add delay of 1 hour to let mirrors be synced before
#
git diff --diff-filter=ACM --name-status "@{ 2 hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s   |\
grep -v -f ~/tb/data/IGNORE_PACKAGES            |\
sort -u > $pks

if [[ ! -s $pks ]]; then
  exit 0
fi

for bl in $(ls ~/run/*/var/tmp/tb/backlog.upd 2>/dev/null)
do
  (uniq $pks | shuf; cat $bl) > $bl.tmp
  # no "mv", that overwrites file permissions
  #
  cp $bl.tmp $bl
  rm $bl.tmp
done
