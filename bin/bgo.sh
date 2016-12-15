#!/bin/sh
#
# set -x

# create a bugz entry at b.g.o
#

# typical call:
#
#  ~/tb/bin/bgo.sh -d ~/run/desktop-unstable_20160916-100730/tmp/issues/20160918-113424_sci-chemistry_reduce-3.16.111118 -b 582084


function errmsg() {
  echo "
  *
  *
  *
  failed with error code $1
  *
  *
  *

  "
  cat bugz.err
}

block=""
comment="same at a tinderbox image"
dir=""
id=""

while getopts a:b:c:d: opt
do
  case $opt in
    a)  id="$OPTARG";;          # attach onto the given id
    b)  block="$OPTARG";;       # block that bug (id or alias)
    c)  comment="$OPTARG";;     # add comment, used with -a
    d)  dir="$OPTARG";;         # issue directory
    *)  echo " not implemented !"
        exit 1;;
  esac
done

if [[ -z "$dir" ]]; then
  exit 1
fi
cd $dir || exit 2

if [[ -f ./.reported ]]; then
  echo
  echo "already reported ! remove $dir/.reported before repeating !"
  echo
  exit 3
fi


# pick up after a possible previous run
#
truncate -s 0 bugz.{out,err}

if [[ -n "$id" ]]; then
  # attach onto an existing bug
  #
  bugz attach --content-type "text/plain" --description "$comment" $id emerge-info.txt 1>>bugz.out 2>>bugz.err || errmsg $?
  rc=$?
  bugz modify -s CONFIRMED $id 1>>bugz.out 2>>bugz.err || errmsg $?

else
  # create a new bug
  #
  bugz post \
    --product "Gentoo Linux"          \
    --component "Current packages"    \
    --version "unspecified"           \
    --title "$(cat ./title)"          \
    --op-sys "Linux"                  \
    --platform "All"                  \
    --priority "Normal"               \
    --severity "Normal"               \
    --alias ""                        \
    --assigned-to "$(cat ./assignee)"       \
    --cc "$(cat cc)"                        \
    --append-command "cat emerge-info.txt"  \
    --description-from "./issue"            \
    --batch                           \
    --default-confirm n               \
    1>>bugz.out 2>>bugz.err
  rc=$?

  id=$(grep ' * Bug .* submitted' bugz.out | sed 's/[^0-9]//g')
  if [[ -z "$id" ]]; then
    errmsg $rc
    echo
    echo "empty bug id"
    echo
    cat bugz.out
    exit 4
  fi
fi

echo
echo "https://bugs.gentoo.org/show_bug.cgi?id=$id"
echo

if [[ $rc -ne 0 || -s bugz.err ]]; then
  errmsg $rc
  exit 5
fi

if [[ -n "$block" ]]; then
  bugz modify --add-blocked "$block" $id 1>>bugz.out 2>>bugz.err || errmsg $?
fi

# attach files
#
for f in files/*
do
  echo "$f" | grep -q "bz2$" && ct="application/x-bzip2" || ct="text/plain"
  echo "  $f"
  bugz attach --content-type "$ct" --description "" $id $f 1>>bugz.out 2>>bugz.err || errmsg $?
done

# avoid duplicate reports
#
touch ./.reported

echo
