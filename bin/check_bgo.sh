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
    assignee=$(cut -f1 -d' ' <<<$m)
    cc=$(cut -f2- -d' ' -s <<<$m)
  fi

  if grep -q 'file collision with' $issuedir/title; then
    # for a file collision report both involved sites
    local collision_partner=$(sed -e 's,.*file collision with ,,' <$issuedir/title)
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    if [[ -n $collision_partner_pkgname ]]; then
      cc="$cc $(equery meta -m $collision_partner_pkgname | grep '@' | xargs)"
    fi

  elif grep -q 'internal compiler error:' $issuedir/title; then
    cc+=" toolchain@gentoo.org"
  fi

  echo "$assignee" >$issuedir/assignee
  if [[ -n $cc ]]; then
    xargs -n 1 <<<$cc | sort -u | grep -v "^$assignee$" | xargs >$issuedir/cc
  fi
  if [[ ! -s $issuedir/cc || -z $cc ]]; then
    rm -f $issuedir/cc
  fi
}

#######################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

issuedir=${1?missing issue dir}
force="n"
if [[ $# -eq 2 && $2 == "-f" ]]; then
  force="y"
fi

trap Exit INT QUIT TERM EXIT
source $(dirname $0)/lib.sh
checkBgo

echo -e "\n===========================================\n"

name=$(cat $issuedir/../../name)                                         # eg.: 17.1-20201022-101504
pkg=$(basename $(realpath $issuedir) | cut -f3- -d'-' -s | sed 's,_,/,') # eg.: net-misc/bird-2.0.7-r1
pkgname=$(qatom $pkg -F "%{CATEGORY}/%{PN}")                             # eg.: net-misc/bird
SetAssigneeAndCc

if [[ -f $issuedir/.reported ]]; then
  echo -e "\n already reported: $(cat $issuedir/.reported)\n $issuedir/.reported\n" >&2
  exit 0
fi
if [[ ! -s $issuedir/title ]]; then
  echo -e "\n no title found\n" >&2
  exit 1
fi

versions=$(
  eshowkw --arch amd64 $pkgname |
    grep -v -e '^  *|' -e '^-' -e '^Keywords' |
    # + == stable, o == masked, ~ == unstable
    awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' |
    xargs
)
if [[ -z $versions ]]; then
  echo "$pkg is unknown" >&2
  exit 1
fi

createSearchString
cmd="$(dirname $0)/bgo.sh -d $issuedir"
blocker_bug_no=$(LookupForABlocker ~tinderbox/tb/data/BLOCKER)
if [[ -n $blocker_bug_no ]]; then
  cmd+=" -b $blocker_bug_no"
fi
echo -e "\n  ${cmd}\n\n"

if [[ $force == "y" ]]; then
  $cmd
else
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
    if [[ $? -eq 2 ]]; then
      exit 2
    fi
    if ! SearchForSimilarIssue; then
      if [[ $? -eq 2 ]]; then
        exit 2
      fi
      # no bug found for that pkg, so file it
      $cmd
    fi
  fi
fi
echo
