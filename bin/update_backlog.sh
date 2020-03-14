#!/bin/bash
#
# set -x

# pick up latest changed package(s) -or- retest package(s) given at the command line
# and merge them into appropriate backlog file(s)
#

export LANG=C.utf8

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

  # add a delay to let Gentoo mirrors be synced already
  #
  git diff --diff-filter=ACM --name-status "@{ 2 hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f2- -s | cut -f1-2 -d'/' -s | uniq |\
  grep -v -f ~/tb/data/IGNORE_PACKAGES > $pks

else
  # use high prio backlog but schedule package(s) after existing entries
  #
  target="1st"

  echo $* | xargs -n 1 | sort -u |\
  while read line
  do
    # split away version/revision if possible
    #
    [[ -z "$line" ]] && continue
    p=$(qatom "$line" | grep -F -v '<unset>' | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
    [[ -z "$p" ]] && p=$line
    echo $p >> $pks

    # delete package from various pattern files
    #
    sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d" \
      ~/tb/data/ALREADY_CATCHED                   \
      ~/run/*/etc/portage/package.mask/self       \
      ~/run/*/etc/portage/package.env/{nosandbox,test-fail-continue} 2>/dev/null
  done
fi

if [[ ! -s $pks ]]; then
  exit 0
fi

for bl in $(ls ~/run/*/var/tmp/tb/backlog.$target 2>/dev/null)
do
  # avoid dups in backlog file
  #
  (uniq $pks | grep -v -f $bl | shuf; cat $bl) > $bl.tmp
  # no "mv", that overwrites file permissions
  #
  cp $bl.tmp $bl
  rm $bl.tmp
done
