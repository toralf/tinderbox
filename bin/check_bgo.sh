#!/bin/bash
# set -x

# check buzilla.gentoo.org whether issue was already reported


function Exit()  {
  local rc=${1:-$?}

  rm -f $tmpfile
  exit $rc
}


function SearchForMatchingBugs() {
  local bsi=$issuedir/bugz_search_items     # use the title as a set of space separated search patterns

  # get away line numbers, certain special terms et al
  sed -e 's,&<[[:alnum:]].*>,,g'  \
      -e 's,/\.\.\./, ,'          \
      -e 's,:[[:alnum:]]*:[[:alnum:]]*: , ,g' \
      -e 's,.* : ,,'              \
      -e 's,[<>&\*\?\!], ,g'      \
      -e 's,[\(\)], ,g'           \
      -e 's,  *, ,g'              \
      $issuedir/title > $bsi

  # search first for the same revision/version,then try only category/package name
  for i in $pkg $pkgname
  do
    bugz -q --columns 400 search --show-status -- $i "$(cat $bsi)" |
        grep -e " CONFIRMED " -e " IN_PROGRESS " | sort -u -n -r | head -n 8 | tee $tmpfile
    if [[ -s $tmpfile ]]; then
      found_issues=1
      return
    fi

    echo -en "$i DUP                    \r"
    bugz -q --columns 400 search --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(cat $bsi)" |\
        sort -u -n -r | head -n 3 | tee $tmpfile
    if [[ -s $tmpfile ]]; then
      found_issues=2
      echo -e " \n^DUPLICATE"
      return
    fi

    echo -en "$i                        \r"
    bugz -q --columns 400 search --show-status --status RESOLVED -- $i "$(cat $bsi)" |\
        sort -u -n -r | head -n 3 | tee $tmpfile
    if [[ -s $tmpfile ]]; then
      found_issues=2
      return
    fi
  done

  if [[ ! -s $tmpfile ]]; then
    # if no findings till now, so search for any bug of that category/package

    local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
    local g='stabilize|Bump| keyword| bump'

    echo -e "OPEN:     $h&resolution=---&short_desc=$pkgname\n"
    bugz -q --columns 400 search --show-status $pkgname |\
        grep -v -i -E "$g" | sort -u -n -r | head -n 8 | tee $tmpfile
    if [[ -s $tmpfile ]]; then
      found_issues=2
    fi

    if [[ $(wc -l < $tmpfile) -lt 5 ]]; then
      echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
      bugz -q --columns 400 search --status RESOLVED $pkgname |\
          grep -v -i -E "$g" | sort -u -n -r | head -n 5 | tee $tmpfile
      if [[ -s $tmpfile ]]; then
        found_issues=2
      fi
    fi
  fi
}


# test title against known blocker
# the BLOCKER file contains paragraphs like:
#   # comment
#   <bug id>
#   <pattern string ready for grep -E>
# if <pattern> is defined more than once then the first makes it
function LookupForABlocker() {
  if [[ ! -s $issuedir/title ]]; then
    return 1
  fi

  while read -r line
  do
    if [[ $line =~ ^# || "$line" = "" ]]; then
      continue
    fi

    if [[ $line =~ ^[0-9].* ]]; then
      read -r number suffix <<< $line
    fi

    if grep -q -E "$line" $issuedir/title; then
      blocker_bug_no=$number
      if [[ -n "$suffix" ]]; then
        if ! grep -q -F " ($suffix)" $issuedir/title; then
          sed -i -e "s,$, ($suffix),g" $issuedir/title
          echo "suffixed title"
        fi
      fi
      break
    fi
  done < <(grep -v -e '^#' -e '^$' ~tinderbox/tb/data/BLOCKER)
}


function SetAssigneeAndCc() {
  local assignee
  local cc
  local m=$(equery meta -m $pkgname | grep '@' | xargs)

  if [[ -z "$m" ]]; then
    assignee="maintainer-needed@gentoo.org"
    cc=""

  elif [[ ! $repo = "gentoo" ]]; then
    if [[ $repo = "science" ]]; then
      assignee="sci@gentoo.org"
    else
      assignee="$repo@gentoo.org"
    fi
    cc="$m"

  elif [[ $name =~ "musl" ]]; then
    assignee="musl@gentoo.org"
    cc="$m"

  else
    assignee=$(cut -f1 -d' ' <<< $m)
    cc=$(cut -f2- -d' ' -s <<< $m)
  fi

  # for a file collision report both involved sites
  if grep -q 'file collision with' $issuedir/title; then
    local collision_partner=$(sed -e 's,.*file collision with ,,' < $issuedir/title)
    collision_partner_pkgname=$(qatom $collision_partner | cut -f1-2 -d' ' -s | tr ' ' '/')
    if [[ -n "$collision_partner_pkgname" ]]; then
      cc="$cc $(equery meta -m $collision_partner_pkgname | grep '@' | xargs)"
    fi
  fi

  echo "$assignee" > $issuedir/assignee
  if [[ -n "$cc" ]]; then
    xargs -n 1 <<< $cc | sort -u | grep -v "^$assignee$" | xargs > $issuedir/cc
  else
    rm -f $issuedir/cc
  fi
}



#######################################################################
set -euf
export LANG=C.utf8

issuedir=~/run/$1

if [[ ! -s $issuedir/title ]]; then
  echo "no title"
  exit 1
fi

if [[ -f $issuedir/.reported ]]; then
  echo "already reported"
  exit 0
fi

trap Exit INT QUIT TERM EXIT
tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.log)

echo
echo "==========================================="
# echo $issuedir

name=$(cat $issuedir/../../../../../etc/conf.d/hostname)      # eg.: 17.1-20201022-101504
repo=$(cat $issuedir/repository)                              # eg.: gentoo
pkg=$(basename $issuedir | cut -f3- -d'-' -s | sed 's,_,/,')  # eg.: net-misc/bird-2.0.7
pkgname=$(qatom $pkg | cut -f1-2 -d' ' -s | tr ' ' '/')       # eg.: net-misc/bird

echo    "    title:    $(cat $issuedir/title)"
echo -n "    versions: "
eshowkw --overlays --arch amd64 $pkgname |\
    grep -v -e '^  *|' -e '^-' -e '^Keywords' |\
    awk '{ if ($3 == "+") { print $1 } else if ($3 == "o") { print "**"$1 } else { print $3$1 } }' |\
    xargs

blocker_bug_no=""
LookupForABlocker
SetAssigneeAndCc
echo "    devs:     $(cat $issuedir/{assignee,cc} 2>/dev/null | xargs)"
echo

found_issues=0
SearchForMatchingBugs

cmd="$(dirname $0)/bgo.sh -d $issuedir"
if [[ -n $blocker_bug_no ]]; then
  cmd+=" -b $blocker_bug_no"
fi

if [[ $found_issues -eq 0 ]]; then
  $cmd
elif [[ $found_issues -eq 2 ]]; then
  echo -e "\n\n    ${cmd}\n"
fi
echo
