#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# create or modify a bug report at https://bugzilla.gentoo.org

function Warn() {
  local rc=$?
  echo "  --------------"
  echo -e "\n  ${1:-<no text given>}, error code: ${2:-$rc}\n\n"
  tail -v bgo.sh.{out,err}
  echo "  --------------"
}

function Exit() {
  local rc=${1:-$?}

  trap - INT QUIT TERM EXIT

  if [[ $rc -ne 0 ]]; then
    Warn "an error occurred" $rc
  fi

  exit $rc
}

function append() {
  local comment="appeared recently at the tinderbox image $name"
  $__tinderbox_bugz_timeout_wrapper modify --status CONFIRMED --comment "$comment" $id >bgo.sh.out 2>bgo.sh.err
  $__tinderbox_bugz_timeout_wrapper modify --status CONFIRMED --comment-from ./comment0 $id >bgo.sh.out 2>bgo.sh.err
}

function create() {
  local title
  title=$(cat ./title)

  if [[ $name =~ "_llvm" ]]; then
    title=$(sed -e 's, - , - [llvm] ,' <<<$title)
  fi

  while read -r dice; do
    title=$(sed -e "s, - , - $dice ," <<<$title)
  done < <(
    grep -hr -v "^#" ../../../../../etc/portage/package.{accept_keywords,unmask}/ |
      grep "# DICE.*\[.*\]" |
      grep -Eo '(\[.*\])' |
      sort -u
  )

  $__tinderbox_bugz_timeout_wrapper post \
    --batch \
    --default-confirm "n" \
    --title "$(cut -c -$__tinderbox_bugz_title_length <<<$title)" \
    --product "Gentoo Linux" \
    --component "Current packages" \
    --version "unspecified" \
    --description-from ./comment0 \
    >bgo.sh.out 2>bgo.sh.err

  id=$(awk '/ * Info: Bug .* submitted/ { print $4 }' bgo.sh.out)
  if [[ -z $id || ! $id =~ ^[0-9]+$ ]]; then
    echo
    echo " wrong bug id: '$id'" >&2
    echo
    Exit 4
  fi

  if grep -q ' fails test -' ./title; then
    $__tinderbox_bugz_timeout_wrapper modify --set-keywords "TESTFAILURE" $id >bgo.sh.out 2>bgo.sh.err || Warn "test keyword"
  fi
}

function attach() {
  echo
  for f in $(
    set +f
    ls ./files/* | sort
  ); do
    local bytes
    bytes=$(wc --bytes <$f)
    if [[ $bytes -eq 0 ]]; then
      echo "skipped empty file: $f" >&2
    # Attachments cannot be more than 1000 KB.
    elif ((bytes > 1000 * 1024)); then
      echo "too big ($((bytes / 1024)) KB): $f"
      local file_size=$(ls -lh $f | awk '{ print $5 }')
      local file_path=$(realpath $f | sed -e "s,^.*img/,,")
      local url="http://tinderbox.zwiebeltoralf.de:31560/$file_path"
      local comment="The file size of $f is too big ($file_size) for an upload. For few weeks the link $url is valid."
      $__tinderbox_bugz_timeout_wrapper modify --comment "$comment" $id >bgo.sh.out 2>bgo.sh.err
    else
      local ct
      case $f in
      *.bz2) ct="application/x-bzip2" ;;
      *.gzip) ct="application/x-gzip" ;;
      *.xz) ct="application/x-xz" ;;
      *) ct="text/plain" ;;
      esac
      echo "  $f"
      $__tinderbox_bugz_timeout_wrapper attach --content-type "$ct" --description "" $id $f >bgo.sh.out 2>bgo.sh.err || Warn "attach $f"
    fi
  done
}

function assign() {
  local assignee
  local cc
  assignee="$(cat ./assignee)"
  if [[ $name =~ "musl" && $assignee != "maintainer-needed@gentoo.org" ]] && ! grep -q -f ~tinderbox/tb/data/CATCH_MISC ./title; then
    assignee="musl@gentoo.org"
    cc="$(cat ./assignee ./cc 2>/dev/null | xargs -n 1 | grep -v "musl@gentoo.org" | xargs)"
  else
    cc="$(cat ./cc 2>/dev/null || true)"
  fi

  if grep -q 'meson' ./title && ! grep -q "eschwartz@gentoo.org" ./assignee ./cc; then
    cc+=" eschwartz@gentoo.org"
  fi

  local add_cc=""
  if [[ -n $cc ]]; then
    add_cc=$(sed 's,  *, --add-cc ,g' <<<" $cc") # leading space is needed
  fi

  $__tinderbox_bugz_timeout_wrapper modify -a $assignee $add_cc $id >bgo.sh.out 2>bgo.sh.err || Warn "to:>$assignee< add_cc:>$add_cc<"
}

#######################################################################
set -euf
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

source $(dirname $0)/lib.sh
checkBgo

block=""
issuedir=""
id=""

while getopts b:d:i: opt; do
  case $opt in
  b) block="$OPTARG" ;;    # (b)lock that bug (id or alias)
  d) issuedir="$OPTARG" ;; # (d)irectory with all files
  i) id="$OPTARG" ;;       # (i)d of an existing bug
  *)
    echo " unknown parameter '$opt'" >&2
    exit 1
    ;;
  esac
done

if [[ -z $issuedir || ! -d $issuedir ]]; then
  echo " wrong issuedir '$issuedir'" >&2
  exit 1
fi
cd $issuedir

if [[ ! -s emerge-info.txt ]]; then
  echo " missing emerge-info.txt" >&2
  exit 1
fi

trap Exit INT QUIT TERM EXIT

# cleanup of a previous run
truncate -s 0 bgo.sh.{out,err}
chmod a+w bgo.sh.{out,err}
name=$(cat ../../name)

if [[ -n $id ]]; then
  new_bug=0
  append
else
  if [[ -f .reported ]]; then
    echo -e "\n already reported: $(cat .reported)\n .reported\n"
    exit 0
  fi

  if [[ ! -s ./assignee ]]; then
    echo " no assignee given, run first check_bgo.sh" >&2
    exit 2
  fi
  if [[ ! -s ./title ]]; then
    echo -e "\n no title found\n" >&2
    exit 2
  fi
  new_bug=1
  create
fi
echo "https://bugs.gentoo.org/$id" | tee -a ./.reported

if [[ -s bgo.sh.err ]]; then
  Exit 5
fi

bugz attach --content-type "text/plain" --description "" $id emerge-info.txt >bgo.sh.out 2>bgo.sh.err || Warn "info"
if [[ -d ./files ]]; then
  attach
fi

if [[ -n $block ]]; then
  $__tinderbox_bugz_timeout_wrapper modify --add-blocked "$block" $id >bgo.sh.out 2>bgo.sh.err || Warn "blocker $block"
fi

# set this as the very last step to reduce the amount of emails send out
if [[ $new_bug -eq 1 ]]; then
  assign
fi

echo
