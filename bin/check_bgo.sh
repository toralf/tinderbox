#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# query buzilla.gentoo.org for given issue


function Exit()  {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT
  exit $rc
}


# check for a blocker/tracker bug
# the BLOCKER file contains tupels like:
#
#   # comment
#   <bug id>
#   <pattern/s>
function LookupForABlocker() {
  while read -r line
  do
    if [[ $line =~ ^[0-9].* ]]; then
      read -r number <<< $line
      continue
    fi

    if grep -q -E "$line" $issuedir/title; then
      blocker_bug_no=$number
      break
    fi
  done < <(grep -v -e '^#' -e '^$' ~tinderbox/tb/data/BLOCKER)
}


function SetAssigneeAndCc() {
  local assignee
  local cc=""
  local m=$(equery meta -m $pkgname | grep '@' | xargs)

  if [[ -z "$m" ]]; then
    assignee="maintainer-needed@gentoo.org"
  else
    assignee=$(cut -f1 -d' ' <<< $m)
    cc=$(cut -f2- -d' ' -s <<< $m)
  fi


  if grep -q 'file collision with' $issuedir/title; then
    # for a file collision report both involved sites
    local collision_partner=$(sed -e 's,.*file collision with ,,' < $issuedir/title)
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    if [[ -n "$collision_partner_pkgname" ]]; then
      cc="$cc $(equery meta -m $collision_partner_pkgname | grep '@' | xargs)"
    fi

  elif grep -q 'internal compiler error:' $issuedir/title; then
    cc+=" toolchain@gentoo.org"
  fi

  echo "$assignee" > $issuedir/assignee
  if [[ -n "$cc" ]]; then
    xargs -n 1 <<< $cc | sort -u | grep -v "^$assignee$" | xargs > $issuedir/cc
  fi
  if [[ ! -s $issuedir/cc || -z "$cc" ]]; then
    rm -f $issuedir/cc
  fi
}



#######################################################################
set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

issuedir=$1

if [[ ! -s $issuedir/title ]]; then
  echo "no title"
  exit 1
elif [[ -f $issuedir/.reported ]]; then
  echo "already reported: $(cat $issuedir/.reported)"
  exit 0
fi

trap Exit INT QUIT TERM EXIT

source $(dirname $0)/lib.sh

name=$(cat $issuedir/../../name)                                                            # eg.: 17.1-20201022-101504
pkg=$(basename $(realpath $issuedir) | cut -f3- -d'-' -s | sed 's,_,/,' | cut -f1 -d ':')   # eg.: net-misc/bird-2.0.7-r1:0
pkgname=$(qatom $pkg -F "%{CATEGORY}/%{PN}")                                                # eg.: net-misc/bird
versions=$(eshowkw --arch amd64 $pkgname |\
            grep -v -e '^  *|' -e '^-' -e '^Keywords' |\
            # + == stable, o == masked, ~ == unstable
            awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' |\
            xargs
          )
if [[ -z $versions ]]; then
  echo "$pkg is unknown"
  exit 1
fi

SetAssigneeAndCc
echo
echo "==========================================="
echo "    title:    $(cat $issuedir/title)"
echo "    versions: $versions"
echo "    devs:     $(cat $issuedir/{assignee,cc} 2>/dev/null | xargs)"

# a (dummy) 2nd parameter skips this check
if [[ $# -lt 2 ]]; then
  keyword=$(grep "^ACCEPT_KEYWORDS=" ~tinderbox/img/$name/etc/portage/make.conf)
  cmd="$keyword ACCEPT_LICENSE=\"*\" portageq best_visible / $pkgname"
  if best=$(eval $cmd); then
    if [[ $pkg != $best ]]; then
      echo -e "\n    is  NOT  latest\n"
      exit 0
    fi
  else
    echo -e "\n    is  not  KNOWN\n"
    exit 0
  fi
fi

echo
createSearchString
if ! SearchForSameIssue || [[ ! $# -lt 2 ]]; then
  cmd="$(dirname $0)/bgo.sh -d $issuedir"

  blocker_bug_no=""
  LookupForABlocker
  if [[ -n $blocker_bug_no ]]; then
    cmd+=" -b $blocker_bug_no"
  fi

  if SearchForSimilarIssue; then
    # do manual inspect results before
    echo -e "\n\n    ${cmd}\n"
  else
    echo -e "\n nothing found in b.g.o -> automatic filing:"
    $cmd
  fi
fi
echo
