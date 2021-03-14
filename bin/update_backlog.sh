#!/bin/bash
# set -x


# merge tree changes or certain packages into appropriate backlogs


function ScanTreeForChanges() {
  repo_path=$(portageq get_repo_path / gentoo) || exit 2
  cd $repo_path || exit 2

  # give mirrors time to sync - 1 hours seems (rarely) too short
  git diff --diff-filter=ACM --name-status "@{ 3 hour ago }".."@{ 2 hour ago }" 2>/dev/null |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f2- -s | cut -f1-2 -d'/' -s | uniq |\
  grep -v -f ~/tb/data/IGNORE_PACKAGES > $result
}


function retestPackages() {
  xargs -n 1 --no-run-if-empty <<< ${@} | sort -u |\
  while read word
  do
    echo "$word" >> $result
    pkgname=$(qatom "$word" | cut -f1-2 -d' ' -s | grep -F -v '<unset>' | tr ' ' '/')
    if [[ -n "$pkgname" ]]; then
      # delete package from global tinderbox file and from image specific files
      sed -i -e "/$(sed -e 's,/,\\/,' <<< $pkgname)/d" \
        ~/tb/data/ALREADY_CATCHED                   \
        ~/run/*/etc/portage/package.mask/self       \
        ~/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null || true
    fi
  done
}


function updateBacklog()  {
  target=$1

  [[ -s $result ]] || return

  for bl in $(ls ~/run/*/var/tmp/tb/backlog.$target 2>/dev/null)
  do
    if [[ $target = "upd" ]]; then
      # re-mix data with backlog
      sort -u $result $bl | shuf > $bl.tmp
    elif [[ $target = "1st" ]]; then
      # put shuffled data (sort out dups before) after current backlog
      (sort -u $result | grep -v -F -f $bl | shuf; cat $bl) > $bl.tmp
    fi

    # no "mv", that would overwrite file permissions
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

result=/tmp/${0##*/}.txt
truncate -s 0 $result

# use update backlog for new and updated portage tree entries
# and high prio backlog to retest package(s)
if [[ $# -eq 0 ]]; then
  ScanTreeForChanges
  updateBacklog "upd"
else
  retestPackages ${@}
  updateBacklog "1st"
fi
