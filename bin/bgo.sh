#!/bin/bash
#
# set -x

export LANG=C.utf8

# create or modify a bug report at http://bugzilla.gentoo.org
#

function Warn() {
  rc=$1

  echo "
  *
  failed with error code $rc in $issuedir
  *
  "
  tail -v bgo.sh.*
  echo "--------------"
}


function Error() {
  rc=$1
  Warn $rc
  exit $rc
}


#######################################################################
#

id=""
block=""
comment=""
issuedir=""
severity="Normal"

newbug=1    # if set to 1 then do neither change To: nor cc:

while getopts b:c:d:i:s: opt
do
  case $opt in
    b)  block="$OPTARG";;       # (b)lock that bug (id or alias)
    c)  comment="$OPTARG";;     # (c)omment, used with -a
    d)  issuedir="$OPTARG";;    # (d)irectory with all files
    i)  id="$OPTARG"            # (i)d of an existing bug
        newbug=0
        ;;
    s)  severity="$OPTARG";;    # "normal", "QA" and so on
    *)  echo " not implemented !"; exit 1;;
  esac
done

if [[ -z "$issuedir" ]]; then
  echo "no issuedir given"
  exit 1
fi

cd $issuedir
if [[ $? -ne 0 ]]; then
  echo "cannot cd into '$issuedir'"
  exit 2
fi

if [[ -f ./.reported ]]; then
  echo "already reported - do :    rm $issuedir/.reported"
  exit 3
fi

# cleanup of a previous run
#
rm -f bgo.sh.{out,err}

if [[ -n "$id" ]]; then
  # modify an existing bug report
  #
  if [[ -z "$comment" ]]; then
    comment="appeared recently at the tinderbox image $(realpath $issuedir | cut -f5 -d'/')"
  fi
  timeout 120 bugz modify --status CONFIRMED --comment "$comment" $id 1>bgo.sh.out 2>bgo.sh.err || Error $?

else
  # create a new bug report
  #
  timeout 120 bugz post \
    --product "Gentoo Linux"          \
    --component "Current packages"    \
    --version "unspecified"           \
    --title "$(cat ./title)"          \
    --op-sys "Linux"                  \
    --platform "All"                  \
    --priority "Normal"               \
    --severity "$severity"            \
    --alias ""                        \
    --description-from "./comment0"   \
    --batch                           \
    --default-confirm n               \
    1>bgo.sh.out 2>bgo.sh.err || Error $?

  id=$(grep ' * Bug .* submitted' bgo.sh.out | sed 's/[^0-9]//g')
  if [[ -z "$id" ]]; then
    echo
    echo "empty bug id"
    echo
    Error 4
  fi

  if [[ -n "$comment" ]]; then
    timeout 120 bugz modify --status CONFIRMED --comment "$comment" $id 1>bgo.sh.out 2>bgo.sh.err || Error $?
  fi

  if [[ -s $issuedir/keywords ]]; then
    cat $issuedir/keywords |\
    while read i
    do
      timeout 120 bugz modify --set-keywords "$i" $id 1>bgo.sh.out 2>bgo.sh.err || Warn $?
    done
  fi
fi

# avoid duplicate reports
#
touch ./.reported

echo
echo "https://bugs.gentoo.org/show_bug.cgi?id=$id"

if [[ -s bgo.sh.err ]]; then
  Error 5
fi

if [[ -f emerge-info.txt ]]; then
  timeout 120 bugz attach --content-type "text/plain" --description "" $id emerge-info.txt 1>bgo.sh.out 2>bgo.sh.err || Warn $?
fi

if [[ -d ./files ]]; then
  echo
  for f in ./files/*
  do
    bytes=$(wc --bytes < $f)
    if [[ $bytes -eq 0 ]]; then
      echo "skipped empty file: $f"
      continue
    fi

    # max. size from b.g.o. is 1000 KB
    #
    if [[ $bytes -gt 1000000 ]]; then
      echo "skipped too fat file: $f"
      continue
    fi

    # x-bzip matches both *.bz2 and *.tbz2
    #
    echo "$f" | grep -q "bz2$" && ct="application/x-bzip" || ct="text/plain"
    echo "  $f"
    timeout 120 bugz attach --content-type "$ct" --description "" $id $f 1>bgo.sh.out 2>bgo.sh.err || Warn $?
  done
fi

if [[ -n "$block" ]]; then
  timeout 120 bugz modify --add-blocked "$block" $id 1>bgo.sh.out 2>bgo.sh.err || Warn $?
fi

# set assignee and cc as the last step to reduce the amount of emails sent out by bugzilla for each change at a bug report
#
if [[ $newbug -eq 1 ]]; then
  assignee="-a $(cat ./assignee)"   # we expect only 1 entry here
  if [[ -s ./cc ]]; then
    cc="$(cat ./cc | grep -v -f ./assignee | xargs | sed 's/ / --add-cc /g')"    # grep is need if eg for musl the assignee was overwritten manually
    if [[ -n "$cc" ]]; then
      cc="--add-cc $cc"
    fi
  fi
  timeout 120 bugz modify $assignee $cc $id 1>bgo.sh.out 2>bgo.sh.err || Warn $?
fi

echo
