# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later

function __has_cgroup() {
  local name=/sys/fs/cgroup/tb/$(basename $1)

  [[ -d $name ]]
}

function __is_cgrouped() {
  local name=/sys/fs/cgroup/tb/$(basename $1)

  __has_cgroup $name && ! grep -q 'populated 0' $name/cgroup.events 2>/dev/null
}

function __is_locked() {
  [[ -d /run/tb/$(basename $1).lock/ ]]
}

function __is_running() {
  __is_locked $1 && __is_cgrouped $1
}

function __is_stopped() {
  ! __is_locked $1 && ! __is_cgrouped $1
}

function __is_crashed() {
  ! __is_running $1 && ! __is_stopped $1
}

function getStartTime() {
  local img=~tinderbox/img/$(basename $1)

  [[ -d $img ]]

  if ! cat $img/var/tmp/tb/setup.timestamp 2>/dev/null; then
    if ! stat -c %Z $img/mnt 2>/dev/null; then
      stat -c %Z $img
    fi
  fi
}

# list if locked and/or symlinked and/or have a cgroup
function list_active_images() {
  (
    ls ~tinderbox/run/ | sort
    ls /run/tb/ | sed -e 's,.lock,,' | sort
    ls -d /sys/fs/cgroup/tb/23.* | sort
  ) 2>/dev/null |
    xargs -r -n 1 basename |
    # use awk to remove dups, b/c "sort -u" would mix ~/img and ~/run and uniq w/o sort wouldn't detect all dups
    awk '!x[$1]++' |
    while read -r i; do
      if [[ -d ~tinderbox/run/$i ]]; then
        echo ~tinderbox/run/"$i"
      elif [[ -d ~tinderbox/img/$i ]]; then
        echo ~tinderbox/img/"$i"
      else
        echo " active image is wrong: '$i'" >&2
      fi
    done
}

function list_images_by_age() {
  ls -d ~tinderbox/${1:-img}/*/ 2>/dev/null |
    sort -k 2 -t '-'
}

function stripQuotesAndMore() {
  # shellcheck disable=SC1112
  sed -e 's,['\''‘’"`•],,g'
}

function filterPlainText() {
  # non-ascii chars and colour sequences e.g. in media-libs/esdl logs
  ansifilter |
    recode --force --quiet ascii 2>/dev/null |
    # left over: �
    sed -e 's,\xEF\xBF\xBD,,g' |
    # UTF-2018+2019 (left+right single quotation mark)
    sed -e 's,\xE2\x80\x98,,g' -e 's,\xE2\x80\x99,,g' |
    # CR/LF
    sed -e 's,\x00,\n,g' -e 's,\r$,\n,g' -e 's,\r,\n,g'
}

function checkBgo() {
  if ! $__tinderbox_bugz_timeout_wrapper -h &>/dev/null; then
    echo " issue: pybugz is b0rken" >&2
    return 1
  fi

  if ! $__tinderbox_bugz_timeout_wrapper -q get 2 &>/dev/null; then
    echo " issue: b.g.o cannot be queried" >&2
    return 1
  fi
}

function prepareResultFile() {
  if [[ ! -f $issuedir/bugz_result ]]; then
    truncate -s 0 $issuedir/bugz_{err,result}
    chmod a+w $issuedir/bugz_{err,result}
  fi
}

function createSearchString() {
  sed -e 's,^.* - ,,' -e 's,[\(\)], ,g' -e 's,QA Notice: ,,' <$issuedir/title | cut -c -$__tinderbox_bugz_title_length
}

# look for a blocker bug id
# the BLOCKER file contains tupels like:
#
#   # comment
#   <bug id>
#   <pattern/s>
function LookupForABlocker() {
  local pattern_file=${1?}

  while read -r line; do
    if [[ $line =~ ^[0-9]+$ ]]; then
      read -r number <<<$line
      continue
    fi

    if grep -q -E "$line" $issuedir/title; then
      echo "$number"
      return 0
    fi
  done < <(grep -v -e '^#' -e '^$' $pattern_file)

  return 1
}

function BgoIssue() {
  grep -q -e '# Error: ' -e ' Bugzilla error: ' -e "^Traceback" -e ' issue: ' $issuedir/bugz_{err,result}
}

function GotResults() {
  [[ -s $issuedir/bugz_result && $(stat -c %s $issuedir/bugz_result) -gt 40 ]]
}

function SearchForSameIssue() {
  local pkg=${1?PKG UNDEFINED}
  local pkgname=${2?PKGNAME UNDEFINED}
  local issuedir=${3?ISSUEDIR UNDEFINED}

  prepareResultFile
  if grep -q 'file collision with' $issuedir/title; then
    collision_partner=$(sed -e 's,.*file collision with ,,' $issuedir/title)
    collision_partner_pkgname=$(qatom -CF "%{CATEGORY}/%{PN}" $collision_partner)
    $__tinderbox_bugz_search_cmd --show-status -- "file collision $pkgname $collision_partner_pkgname" 2>$issuedir/bugz_err |
      grep -e " UNCONFIRMED " -e " CONFIRMED " -e " IN_PROGRESS " |
      stripQuotesAndMore |
      filterPlainText |
      sed -e '/^$/d' |
      sort -n -r |
      head -n 4 |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi

  else
    for i in $pkg $pkgname; do
      $__tinderbox_bugz_search_cmd --show-status -- $i "$(createSearchString)" 2>$issuedir/bugz_err |
        grep -e " UNCONFIRMED " -e " CONFIRMED " -e " IN_PROGRESS " |
        stripQuotesAndMore |
        filterPlainText |
        sed -e '/^$/d' |
        sort -n -r |
        head -n 4 |
        tee $issuedir/bugz_result
      if BgoIssue; then
        return 1
      elif GotResults; then
        return 0
      fi
    done
  fi

  return 1
}

function SearchForSimilarIssue() {
  local pkg=${1?PKG UNDEFINED}
  local pkgname=${2?PKGNAME UNDEFINED}

  prepareResultFile
  # resolved does not fit our definition of "opened same issue"
  for i in $pkg $pkgname; do
    $__tinderbox_bugz_search_cmd --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(createSearchString)" 2>$issuedir/bugz_err |
      stripQuotesAndMore |
      filterPlainText |
      sed -e '/^$/d' |
      sort -n -r |
      head -n 4 |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      echo -e " \n^^ DUPLICATE\n"
      return 0
    fi

    $__tinderbox_bugz_search_cmd --show-status --status RESOLVED -- $i "$(createSearchString)" 2>$issuedir/bugz_err |
      stripQuotesAndMore |
      filterPlainText |
      sed -e '/^$/d' |
      sort -n -r |
      head -n 4 |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi
  done

  local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
  local g='stabilize|Bump| keyword| bump'

  echo -e "OPEN:     $h&resolution=---&short_desc=$pkgname\n"
  $__tinderbox_bugz_search_cmd --show-status $pkgname 2>$issuedir/bugz_err |
    grep -v -i -E "$g" |
    stripQuotesAndMore |
    filterPlainText |
    sed -e '/^$/d' |
    sort -n -r |
    head -n 12 |
    tee $issuedir/bugz_result
  if BgoIssue; then
    return 1
  elif GotResults; then
    return 0
  fi

  if [[ $(wc -l <$issuedir/bugz_result) -lt 5 ]]; then
    echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
    $__tinderbox_bugz_search_cmd --status RESOLVED $pkgname 2>$issuedir/bugz_err |
      grep -v -i -E "$g" |
      stripQuotesAndMore |
      filterPlainText |
      sed -e '/^$/d' |
      sort -n -r |
      head -n 5 |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi
  fi

  return 1
}

# handle pybugz hang if b.g.o. is down
__tinderbox_bugz_timeout_wrapper="timeout --signal=15 --kill-after=1m 3m bugz"
__tinderbox_bugz_search_cmd="$__tinderbox_bugz_timeout_wrapper -q --columns 400 search"

# Summary is length limited, see https://github.com/toralf/tinderbox/issues/6
__tinderbox_bugz_title_length=170
