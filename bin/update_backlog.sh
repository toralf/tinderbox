#!/bin/bash
#
# set -x

# pick up latest changed packages and merge them into backlog.upd
#

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo "You are not tinderbox !"
  exit 1
fi

repo_path=$( portageq get_repo_path / gentoo ) || exit 2
cd $repo_path || exit 3

# list of updated package(s)
#
pks=/tmp/$(basename $0).txt

# default: 1 hour to let mirrors be synced
#
git diff --diff-filter=ACM --name-status "@{ ${1:-2} hour ago }".."@{ ${1:-1} hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s   |\
grep -v -f ~/tb/data/IGNORE_PACKAGES            |\
sort --unique > $pks

if [[ -s $pks ]]; then
  for i in $(ls ~/run 2>/dev/null)
  do
    # fs is not (yet) mounted)?
    if [[ ! -e ~/run/$i/tmp/ ]]; then
      continue
    fi

    bl=~/run/$i/tmp/backlog.upd
    sort --unique $bl $pks | shuf > $bl.tmp
    # "mv" overwrites file permissions
    #
    cp $bl.tmp $bl
    rm $bl.tmp
  done
fi
