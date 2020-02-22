#!/bin/bash
#
# set -x

# pick up latest changed packages -or- retest packages given at the command line
#  and merge them into appropriate backlog files
#

export LANG=C

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You are not tinderbox !"
  exit 1
fi

# hold updated package(s) here
#
pks=/tmp/${0##*/}.txt
truncate -s 0 $pks

if [[ $# -eq 0 ]]; then
  target="upd"

  repo_path=$(portageq get_repo_path / gentoo) || exit 2
  cd $repo_path || exit 3

  # if called hourly then add delay of 1 hour to let mirrors be synced before
  #
  git diff --diff-filter=ACM --name-status "@{ 2 hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s   |\
  grep -v -f ~/tb/data/IGNORE_PACKAGES            |\
  sort -u > $pks

else
  # use high prio backlog but schedule package(s) after existing entries and avoid dups
  #
  target="1st"

  echo $* | xargs -n 1 | sort -u |\
  while read line
  do
    # split away version/revision if possible
    #
    p=$(qatom "$line" | grep -F -v '<unset>' | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
    [[ -z "$p" ]] && p=$line

    # delete package from various pattern files
    #
    sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d" \
      ~/tb/data/ALREADY_CATCHED                   \
      ~/run/*/etc/portage/package.mask/self       \
      ~/run/*/etc/portage/package.env/{nosandbox,test-fail-continue} 2>/dev/null

    echo $p >> $pks
  done
fi

if [[ ! -s $pks ]]; then
  exit 0
fi

for bl in $(ls ~/run/*/var/tmp/tb/backlog.$target 2>/dev/null)
do
  (uniq $pks | grep -v -f $bl | shuf; cat $bl) > $bl.tmp
  # no "mv", that overwrites file permissions
  #
  cp $bl.tmp $bl
  rm $bl.tmp
done
