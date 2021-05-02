#!/bin/bash
# set -x


# merge either tree changes -or- given package/s into dedicated backlog


function GetTreeChanges() {
  repo_path=$(portageq get_repo_path / gentoo) || exit 2
  cd $repo_path || exit 2

  # give mirrors time to sync - 1 hours seems (rarely) too short
  git diff --diff-filter=ACM --name-status "@{ 3 hour ago }".."@{ 2 hour ago }" 2>/dev/null |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f2- -s | cut -f1-2 -d'/' -s | uniq |\
  grep -v -f ~/tb/data/IGNORE_PACKAGES > $result
}


function ScheduleRetest() {
  xargs -n 1 --no-run-if-empty <<< ${@} |\
  sort -u |\
  while read -r word
  do
    echo "$word" >> $result
    pkgname=$(qatom "$word" 2>/dev/null | cut -f1-2 -d' ' -s | grep -F -v '<unset>' | tr ' ' '/')
    if [[ -n "$pkgname" ]]; then
      # delete package from global tinderbox file and from image specific files
      sed -i -e "/$(sed -e 's,/,\\/,' <<< $pkgname)/d"  \
          ~/tb/data/ALREADY_CATCHED                     \
          ~/run/*/etc/portage/package.mask/self         \
          ~/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} \
          2>/dev/null || true
    fi
  done
}


function updateBacklog()  {
  for i in $(__list_images)
  do
    local bl=$i/var/tmp/tb/backlog.$target
    if [[ $target = "upd" ]]; then
      # mix results into backlog
      sort -u $result $bl | shuf > $bl.tmp
    elif [[ $target = "1st" ]]; then
      # put shuffled data (grep out dups before) ahead of backlog
      (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    fi

    # no "mv", "cp" keeps file permissions and inode
    cp $bl.tmp $bl
    rm $bl.tmp
  done
}


#######################################################################
set -eu
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

source $(dirname $0)/lib.sh

result=/tmp/${0##*/}.txt  # package/s for the appropriate backlog
truncate -s 0 $result

if [[ $# -eq 0 ]]; then
  target="upd"
  GetTreeChanges
else
  target=${1:-upd}
  shift
  ScheduleRetest ${@}
fi

if [[ -s $result ]]; then
 updateBacklog
fi

# keep the result file
