#!/bin/sh
#
# set -x

# pick up latest ebuilds from Git repository and put them on top of applicable backlogs
#

mailto="tinderbox@zwiebeltoralf.de"

iam=$(whoami)
if [[ ! "$iam" = "tinderbox" ]]; then
  echo "wrong user '$iam' !"
  exit 1
fi

# collect all backlog filenames if the image ...
#   1. is symlinked to ~/run
#   2. is running (LOCK and no STOP)
#   3. has a non-empty backlog
#   4. doesn't have any special entries in its backlog
#
applicable=""
for i in ~/run/*
do
  if [[ ! -f $i/tmp/LOCK ]]; then
    continue
  fi

  if [[ -f $i/tmp/STOP ]]; then
    continue
  fi

  backlog=$i/tmp/backlog
  if [[ ! -s $backlog ]]; then
    continue
  fi

  # do not change a backlog if a special action is scheduled
  #
  grep -q -E "^(STOP|INFO|%|@|#)" $backlog
  if [[ $? -eq 0 ]]; then
    continue
  fi

  # in favour of a better coverage keep update_backlog.sh away from every n-th image
  #
  if [[ $(($RANDOM % 2)) -eq 0 ]]; then
    continue
  fi

  applicable="$applicable $backlog"
done

if [[ -z "$applicable" ]]; then
  exit 0
fi

# holds the package names of added/changed/modified/renamed ebuilds
#
acmr=$(mktemp /tmp/acmrXXXXXX)

# add 1 hour to let mirrors be in sync with master
#
cd /usr/portage/
git diff --diff-filter=ACMR --name-status "@{ ${1:-2} hour ago }".."@{ 1 hour ago }" 2>/dev/null |\
grep -F -e '/files/' -e '.ebuild' -e '/Manifest' | cut -f2- -s | xargs -n 1 | cut -f1-2 -d'/' -s | sort --unique > $acmr

info="# $(basename $0) at $(date): $(wc -l < $acmr) ACMR packages"
echo $info

if [[ ! -s $acmr ]]; then
  # append the packages onto applicable backlogs
  #
  for backlog in $applicable
  do
    echo $backlog
    echo "$info" >> $backlog

    # shuffle packages around in a different way for each backlog
    # limit amount of injected packages
    #
    sort --random-sort < $acmr | head -n 100 >> $backlog
  done
fi

rm $acmr
