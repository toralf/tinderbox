#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# query buzilla.gentoo.org for given issue

function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT
  exit $rc
}

function SetAssigneeAndCc() {
  local assignee
  local cc=""

  local m=$(equery meta -m $pkgname | grep '@' | xargs)
  if [[ -z $m ]]; then
    assignee="maintainer-needed@gentoo.org"
  else
    assignee=$(cut -f 1 -d ' ' <<<$m)
    cc+=" $(cut -f 2- -d ' ' -s <<<$m)"
  fi

  if grep -q 'file collision with' $issuedir/title; then
    local collision_partner
    collision_partner=$(sed -e 's,.*file collision with ,,' $issuedir/title)
    local collision_partner_pkgname
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    if [[ -n $collision_partner_pkgname ]]; then
      cc+=" $(equery meta -m $collision_partner_pkgname | grep '@' | xargs)"
    fi

  elif grep -q 'internal compiler error:' $issuedir/title; then
    cc+=" toolchain@gentoo.org"
  fi

  if [[ $pkgname =~ "dotnet" ]]; then
    cc+=" xgqt@gentoo.org"
  fi

  echo "$assignee" >$issuedir/assignee
  chmod a+w $issuedir/assignee
  xargs -n 1 <<<$cc | sort -u | grep -v -e "^$assignee$" -e 'proxy-maint@gentoo.org' | xargs >$issuedir/cc
  if [[ -s $issuedir/cc ]]; then
    chmod a+w $issuedir/cc
  else
    rm -f $issuedir/cc
  fi
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

issuedir=${1?missing issue dir}
if [[ -z $issuedir || ! -d $issuedir ]]; then
  echo " wrong issuedir '$issuedir'" >&2
  exit 1
fi

force="n"
if [[ $# -eq 2 && $2 == "-f" ]]; then
  force="y"
fi

trap Exit INT QUIT TERM EXIT
source $(dirname $0)/lib.sh

echo -e "\n===========================================\n"

last_sync=$(stat -c %Z /var/db/repos/gentoo/.git/FETCH_HEAD)
if [[ $((EPOCHSECONDS - last_sync)) -ge 3600 ]]; then
  emaint sync --auto
  echo
fi

name=$(cat $issuedir/../../name)                                           # e.g.: 17.1-20201022-101504
pkg=$(basename $(realpath $issuedir) | cut -f 3- -d '-' -s | sed 's,_,/,') # e.g.: net-misc/bird-2.0.7-r1
pkgname=$(qatom $pkg -F "%{CATEGORY}/%{PN}")                               # e.g.: net-misc/bird
SetAssigneeAndCc

if [[ -f $issuedir/.reported ]]; then
  echo -e "\n already reported: $(cat $issuedir/.reported)\n $issuedir/.reported\n" >&2
  exit 0
fi
if [[ ! -s $issuedir/title ]]; then
  echo -e "\n no title found\n" >&2
  exit 1
fi

cmd="$(dirname $0)/bgo.sh -d $issuedir"
if blocker_bug_no=$(LookupForABlocker ~tinderbox/tb/data/BLOCKER); then
  cmd+=" -b $blocker_bug_no"
fi
echo -e "\n  ${cmd}\n\n"

if [[ $force == "y" ]]; then
  $cmd
else
  createSearchString
  versions=$(
    eshowkw --arch amd64 $pkgname |
      grep -v -e '^  *|' -e '^-' -e '^Keywords' |
      # + == stable, o == masked, ~ == unstable
      awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' |
      xargs
  )
  if [[ -z $versions ]]; then
    echo -e "\n $pkg is has no version ?!\n" >&2
    exit 1
  fi

  cat <<EOF
    title:    $(cat $issuedir/title)
    versions: $versions
    devs:     $(cat $issuedir/{assignee,cc} 2>/dev/null | xargs)
EOF

  if [[ $# -eq 1 ]]; then
    keyword=$(grep "^ACCEPT_KEYWORDS=" ~tinderbox/img/$name/etc/portage/make.conf)
    if best=$(eval "$keyword ACCEPT_LICENSE=\"*\" portageq best_visible / $pkgname"); then
      if [[ $pkg != "$best" ]]; then
        echo -e "\n    is  NOT  latest\n"
        exit 0
      fi
    else
      echo -e "\n    is  not  KNOWN\n"
      exit 0
    fi
  fi
  echo

  if ! SearchForSameIssue; then
    if ! BgoIssue; then
      if ! SearchForSimilarIssue; then
        if ! BgoIssue; then
          echo -e "\n  nothing found for that pkg\n"
          $cmd
        fi
      fi
    fi
  fi
fi
echo
