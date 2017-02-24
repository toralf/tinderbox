#!/bin/sh
#
# set -x

# create or modify an bug report at http://bugzilla.gentoo.org
#

# typical call:
#
#  bgo.sh -d ~/run/desktop-unstable_20160916-100730/tmp/issues/20160918-113424_sci-chemistry_reduce-3.16.111118 -b 582084


function errmsg() {
  echo "
  *
  failed with error code $1
  *

  "
  tail -v bugz.*
}


id=""
block=""
comment="same at a tinderbox image"
dir=""
severity="Normal"

while getopts a:b:c:d:s: opt
do
  case $opt in
    a)  id="$OPTARG";;          # attach onto the given id
    b)  block="$OPTARG";;       # block that bug (id or alias)
    c)  comment="$OPTARG";;     # add comment, used with -a
    d)  dir="$OPTARG";;         # issue directory
    s)  severity="$OPTARG";;     # "normal", "QA" and so on
    *)  echo " not implemented !"
        exit 1;;
  esac
done

if [[ -z "$dir" ]]; then
  exit 1
fi

cd $dir || exit 2

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
