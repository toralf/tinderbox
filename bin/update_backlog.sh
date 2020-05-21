#!/bin/bash


# merge tree changes or certain packages into appropriate backlogs


function updateBacklogs() {
  repo_path=$(portageq get_repo_path / gentoo) || exit 2
  cd $repo_path || exit 2

  # add a delay to let Gentoo mirrors be synced already
  git diff --diff-filter=ACM --name-status "@{ 2 hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
  grep -F -e '/files/' -e '.ebuild' -e 'Manifest' |\
  cut -f2- -s | cut -f1-2 -d'/' -s | uniq |\
  grep -v -f ~/tb/data/IGNORE_PACKAGES > $result
}


function retestPackages() {
  echo $* | xargs -n 1 | sort -u |\
  while read line
  do
    [[ -z "$line" ]] && continue

    # split away version/revision if possible
    p=$(qatom "$line" | grep -F -v '<unset>' | sed 's/[ ]*(null)[ ]*//g' | cut -f1-2 -d' ' -s | tr ' ' '/')
    [[ -z "$p" ]] && p=$line
    echo $p >> $result

    # delete package both from global tinderbox and from image specific portage files
    sed -i -e "/$(echo $p | sed -e 's,/,\\/,')/d" \
      ~/tb/data/ALREADY_CATCHED                   \
      ~/run/*/etc/portage/package.mask/self       \
      ~/run/*/etc/portage/package.env/{cflags_default,nosandbox,test-fail-continue} 2>/dev/null
  done
}


#######################################################################
#
export LANG=C.utf8

if [[ ! "$(whoami)" = "tinderbox" ]]; then
  echo " you must be tinderbox"
  exit 1
fi

result=/tmp/${0##*/}.txt
truncate -s 0 $result

if [[ $# -eq 0 ]]; then
  # use update backlog for new and updated portage tree entries
  target="upd"
  updateBacklogs
else
  # use high prio backlog for retest of package(s)
  target="1st"
  retestPackages $*
fi

if [[ -s $result ]]; then
  for bl in $(ls ~/run/*/var/tmp/tb/backlog.$target 2>/dev/null)
  do
    if [[ $target = "upd" ]]; then
      # re-mix them
      cat $result $bl | sort -u | shuf > $bl.tmp
    elif [[ $target = "1st" ]]; then
      # schedule shuffled new data after existing entries, sort out dups before
      (sort -u $result | grep -v -f $bl | shuf; cat $bl) > $bl.tmp
    fi

    # no "mv", that overwrites file permissions
    cp $bl.tmp $bl
    rm $bl.tmp
  done
fi
