# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later

function __is_cgrouped() {
  local name=/sys/fs/cgroup/tb/$(basename $1)

  [[ -d $name ]] && ! grep -q 'populated 0' $name/cgroup.events 2>/dev/null
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

  cat $img/var/tmp/tb/setup.timestamp 2>/dev/null || stat -c %Z $img 2>/dev/null
}

function stripQuotesAndMore() {
  # shellcheck disable=SC1112
  sed -e 's,['\''‘’"`•],,g'
}

# list if locked and/or symlinked to ~run and/or have a cgroup
function list_active_images() {
  (
    ls ~tinderbox/run/ | sort
    ls /run/tb/ | sed -e 's,.lock,,' | sort
    ls -d /sys/fs/cgroup/tb/[12]?.* | sort
  ) 2>/dev/null |
    xargs -r -n 1 basename |
    # sort -u would mix ~/img and ~/run, uniq would not detect all dups, therefore use awk
    awk '!x[$0]++' |
    while read -r i; do
      if [[ -d ~tinderbox/run/$i ]]; then
        echo ~tinderbox/run/"$i"
      elif [[ -d ~tinderbox/img/$i ]]; then
        echo ~tinderbox/img/"$i"
      fi
    done
}

function list_images_by_age() {
  ls -d ~tinderbox/${1?}/*/ 2>/dev/null |
    sort -k 2 -t '-'
}

# filter leftover of ansifilter
function filterPlainText() {
  # UTF-2018+2019 (left+right single quotation mark)
  sed -e 's,\xE2\x80\x98,,g' -e 's,\xE2\x80\x99,,g' |
    perl -wne '
      s,\x00,\n,g;
      s,\r\n,\n,g;
      s,\r,\n,g;
      print;
  '
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
  # shellcheck disable=SC2154
  if [[ ! -f $issuedir/bugz_result ]]; then
    truncate -s 0 $issuedir/bugz_result
    chmod a+w $issuedir/bugz_result # created by root, writeable by tinderbox
  fi
}

function getSearchString() {
  sed -e 's,^.* - ,,' -e 's,[\(\)], ,g'
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
  grep -q -e "^Traceback" -e " issue: " $issuedir/bugz_result
}

function GotResults() {
  [[ -s $issuedir/bugz_result ]]
}

function SearchForSameIssue() {
  prepareResultFile
  if grep -q 'file collision with' $issuedir/title; then
    collision_partner=$(sed -e 's,.*file collision with ,,' $issuedir/title)
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    # shellcheck disable=SC2154
    $__tinderbox_bugz_search_cmd --show-status -- "file collision $pkgname $collision_partner_pkgname" |
      stripQuotesAndMore |
      grep -e " UNCONFIRMED " -e " CONFIRMED " -e " IN_PROGRESS " |
      sort -n -r |
      head -n 4 |
      filterPlainText |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi

  else
    # shellcheck disable=SC2154
    for i in $pkg $pkgname; do
      $__tinderbox_bugz_search_cmd --show-status -- $i "$(cut -c -$__tinderbox_bugz_title_length $issuedir/title | getSearchString)" |
        stripQuotesAndMore |
        grep -e " UNCONFIRMED " -e " CONFIRMED " -e " IN_PROGRESS " |
        sort -n -r |
        head -n 4 |
        filterPlainText |
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
  prepareResultFile
  # resolved does not fit "same issue"
  for i in $pkg $pkgname; do
    $__tinderbox_bugz_search_cmd --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(getSearchString <$issuedir/title)" |
      stripQuotesAndMore |
      sort -n -r |
      head -n 3 |
      filterPlainText |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      echo -e " \n^^ DUPLICATE\n"
      return 0
    fi

    $__tinderbox_bugz_search_cmd --show-status --status RESOLVED -- $i "$(getSearchString <$issuedir/title)" |
      stripQuotesAndMore |
      sort -n -r |
      head -n 3 |
      filterPlainText |
      tee $issuedir/bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi
  done

  # now search without version/revision

  local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
  local g='stabilize|Bump| keyword| bump'

  echo -e "OPEN:     $h&resolution=---&short_desc=$pkgname\n"
  $__tinderbox_bugz_search_cmd --show-status $pkgname |
    grep -v -i -E "$g" |
    sort -n -r |
    head -n 12 |
    filterPlainText |
    tee $issuedir/bugz_result
  if BgoIssue; then
    return 1
  elif GotResults; then
    return 0
  fi

  if [[ $(wc -l <$issuedir/bugz_result) -lt 5 ]]; then
    echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
    $__tinderbox_bugz_search_cmd --status RESOLVED $pkgname |
      stripQuotesAndMore |
      grep -v -i -E "$g" |
      sort -n -r |
      head -n 5 |
      filterPlainText |
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
