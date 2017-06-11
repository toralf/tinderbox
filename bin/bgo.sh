#!/bin/sh
#
# set -x

# create or modify an bug report at http://bugzilla.gentoo.org
#

# typical call:
#
#  bgo.sh -d ~/run/desktop-unstable_20160916-100730/tmp/issues/20160918-113424_sci-chemistry_reduce-3.16.111118 -b 582084


function errmsg() {
  rc=$1

  echo "
  *
  failed with error code $1
  *

  "
  tail -v bugz.*

  exit $rc
}


id=""
block=""
comment="<unset>"
dir=""
severity="Normal"

while getopts a:b:c:d:i:s: opt
do
  case $opt in
    i)  id="$OPTARG";;          # (i)d of an already existing bug
    b)  block="$OPTARG";;       # (b)lock that bug (id or alias)
    c)  comment="$OPTARG";;     # (c)omment, used with -a
    d)  dir="$OPTARG";;         # (d)irectory with all files
    s)  severity="$OPTARG";;    # "normal", "QA" and so on
    *)  echo " not implemented !"; exit 1;;
  esac
done

if [[ -z "$dir" ]]; then
  echo "no dir given"
  exit 1
fi

cd $dir
if [[ $? -ne 0 ]]; then
  echo "cannot cd into '$dir'"
  exit 2
fi

if [[ -f ./.reported ]]; then
  echo "already reported ! remove $dir/.reported before repeating !"
  exit 3
fi

if [[ ! -f ./issue ]]; then
  echo "did not found mandatory file(s) !"
  exit 4
fi

# pick up after from a previous call
#
truncate -s 0 bugz.{out,err}

if [[ -n "$id" ]]; then
  # modify an existing bug report
  #
  if [[ "$comment" = "<unset>" ]]; then
    comment="same at the tinderbox image $(readlink -f $dir | cut -f5 -d'/')"
  fi
  bugz modify --status CONFIRMED --comment "$comment" $id 1>>bugz.out 2>>bugz.err || errmsg $?

else
  # create a new bug report
  #
  bugz post \
    --product "Gentoo Linux"          \
    --component "Current packages"    \
    --version "unspecified"           \
    --title "$(cat ./title)"          \
    --op-sys "Linux"                  \
    --platform "All"                  \
    --priority "Normal"               \
    --severity "$severity"            \
    --alias ""                        \
    --assigned-to "$(cat ./assignee)" \
    --cc "$(cat cc)"                  \
    --description-from "./issue"      \
    --batch                           \
    --default-confirm n               \
    1>>bugz.out 2>>bugz.err || errmsg $?

  id=$(grep ' * Bug .* submitted' bugz.out | sed 's/[^0-9]//g')
  if [[ -z "$id" ]]; then
    echo
    echo "empty bug id"
    echo
    errmsg 4
  fi
fi

echo
echo "https://bugs.gentoo.org/show_bug.cgi?id=$id"

if [[ -s bugz.err ]]; then
  errmsg 5
fi

if [[ -f emerge-info.txt ]]; then
  bugz attach --content-type "text/plain" --description "" $id emerge-info.txt 1>>bugz.out 2>>bugz.err || errmsg $?
fi

# attach all in ./files
#
if [[ -d ./files ]]; then
  echo
  for f in files/*
  do
    # this matches both *.bz2 and *.tbz2
    #
    echo "$f" | grep -q "bz2$" && ct="application/x-bzip" || ct="text/plain"
    echo "  $f"
    bugz attach --content-type "$ct" --description "" $id $f 1>>bugz.out 2>>bugz.err || errmsg $?
  done
fi

if [[ -n "$block" ]]; then
  bugz modify --add-blocked "$block" $id 1>>bugz.out 2>>bugz.err || errmsg $?
fi

# avoid duplicate reports
#
touch ./.reported

echo
