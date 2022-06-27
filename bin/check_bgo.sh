#!/bin/bash
# set -x

# check buzilla.gentoo.org whether issue was already reported


function Exit()  {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT

  rm -rf $rawfile $resultfile
  exit $rc
}


function ExitfBgoIsDown() {
  if grep -q -F -e 'Error: Bugzilla error:' $rawfile; then
    {
      echo -e "\n b.g.o. is down\n" >&2
      #cat $rawfile >&2
    }
    return 1
  fi
}


function GotFindings() {
  [[ -s $resultfile ]]
}


function SearchForMatchingBugs() {
  # for a file collision report both involved sites
  if grep -q 'file collision with' $issuedir/title; then
    local collision_partner=$(sed -e 's,.*file collision with ,,' < $issuedir/title)
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    bugz -q --columns 400 search --show-status -- "file collision $pkgname $collision_partner_pkgname" |\
        tee $rawfile |\
        grep -e " CONFIRMED " -e " IN_PROGRESS " |\
        sort -u -n -r |\
        head -n 8 |\
        tee $resultfile
    ExitfBgoIsDown
    if GotFindings; then
      return 0
    fi
  fi

  local bsi=$issuedir/bugz_search_items     # transform the issue of the title into space separated search items
  sed -e 's,^.* - ,,'     \
      -e 's,/\.\.\./, ,'  \
      -e 's,[\(\)], ,g'   \
      -e 's,\s\s*, ,g'    \
      $issuedir/title > $bsi

  # look first for version+revision, then look for category/package name
  for i in $pkg $pkgname
  do
    bugz -q --columns 400 search --show-status -- $i "$(cat $bsi)" |\
        tee $rawfile |\
        grep -e " CONFIRMED " -e " IN_PROGRESS " |\
        sort -u -n -r |\
        head -n 8 |\
        tee $resultfile
    ExitfBgoIsDown
    if GotFindings; then
      return 0
    fi

    echo -en "$i DUP                    \r"
    bugz -q --columns 400 search --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(cat $bsi)" |\
        tee $rawfile |\
        sort -u -n -r |\
        head -n 3 |\
        tee $resultfile
    ExitfBgoIsDown
    if GotFindings; then
      echo -e " \n^^ DUPLICATE\n"
      return 1
    fi

    echo -en "$i                        \r"
    bugz -q --columns 400 search --show-status --status RESOLVED -- $i "$(cat $bsi)" |\
        tee $rawfile |\
        sort -u -n -r |\
        head -n 3 |\
        tee $resultfile
    ExitfBgoIsDown
    if GotFindings; then
      return 1
    fi
  done

  if [[ ! -s $resultfile ]]; then
    # if no findings till now, so search for any bug of that category/package

    local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
    local g='stabilize|Bump| keyword| bump'

    echo -e "OPEN:     $h&resolution=---&short_desc=$pkgname\n"
    bugz -q --columns 400 search --show-status $pkgname |\
        tee $rawfile |\
        grep -v -i -E "$g" |\
        sort -u -n -r |\
        head -n 8 |\
        tee $resultfile
    ExitfBgoIsDown
    if GotFindings; then
      something_found=1
    fi

    if [[ $(wc -l < $resultfile) -lt 5 ]]; then
      echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
      bugz -q --columns 400 search --status RESOLVED $pkgname |\
          tee $rawfile |\
          grep -v -i -E "$g" |\
          sort -u -n -r |\
          head -n 5 |\
          tee $resultfile
      ExitfBgoIsDown
      if GotFindings; then
        something_found=1
      fi
    fi
  fi

  return 1
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
  echo "already reported"
  # a 2nd parameter let continue
  [[ $# -lt 2 ]] && exit 0
fi

resultfile=$(mktemp /tmp/$(basename $0)_XXXXXX.result)
rawfile=$(mktemp /tmp/$(basename $0)_XXXXXX.raw)

trap Exit INT QUIT TERM EXIT

name=$(cat $issuedir/../../name)                                          # eg.: 17.1-20201022-101504
pkg=$(basename $(realpath $issuedir) | cut -f3- -d'-' -s | sed 's,_,/,')  # eg.: net-misc/bird-2.0.7-r1
pkgname=$(qatom $pkg -F "%{CATEGORY}/%{PN}")                              # eg.: net-misc/bird
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

blocker_bug_no=""
LookupForABlocker
SetAssigneeAndCc

echo
echo "==========================================="
echo "    title:    $(cat $issuedir/title)"
echo "    versions: $versions"
echo "    devs:     $(cat $issuedir/{assignee,cc} 2>/dev/null | xargs)"

keyword=$(grep "^ACCEPT_KEYWORDS=" ~tinderbox/img/$name/etc/portage/make.conf)
cmd="$keyword ACCEPT_LICENSE=\"*\" portageq best_visible / $pkgname"
if best=$(eval $cmd); then
  if [[ $pkg != $best ]]; then
    echo -e "\n    is  NOT  latest"
    [[ $# -lt 2 ]] && exit 0
  fi
else
  echo -e "\n    is  not  KNOWN"
  [[ $# -lt 2 ]] && exit 0
fi
echo

something_found=0
if SearchForMatchingBugs; then
  echo -e "\n\ was already filed"
else
  cmd="$(dirname $0)/bgo.sh -d $issuedir"
  if [[ -n $blocker_bug_no ]]; then
    cmd+=" -b $blocker_bug_no"
  fi

  if [[ $something_found -eq 0 ]]; then
    echo -e "\n nothing found in b.g.o -> automatic filing:"
    $cmd
  else
    # some similar records were found -> manual inspect needed
    echo -e "\n\n    ${cmd}"
  fi
fi
echo
