# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later

function __is_cgrouped() {
  [[ -d /sys/fs/cgroup/cpu/local/tb/$(basename $1)/ ]]
}

function __is_locked() {
  [[ -d /run/tinderbox/$(basename $1).lock/ ]]
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
  local img
  img=~tinderbox/img/$(basename $1)
  cat $img/var/tmp/tb/setup.timestamp 2>/dev/null || stat -c %Z $img
}

# list if locked and/or symlinked to ~run and/or have a cgroup
function list_active_images() {
  (
    ls ~tinderbox/run/ | sort
    ls /run/tinderbox/ | sed -e 's,.lock,,' | sort
    ls -d /sys/fs/cgroup/cpu/local/tb/??.* | sort
  ) 2>/dev/null |
    xargs -r -n 1 basename |
    # sort -u would mix ~/img and ~/run, uniq would not detect all dups, therefore use awk
    awk '!x[$0]++' |
    while read -r i; do
      if [[ -d ~tinderbox/run/$i ]]; then
        echo ~tinderbox/run/"$i"
      else
        echo ~tinderbox/img/"$i"
      fi
    done
}

function list_images_by_age() {
  ls -d ~tinderbox/${1?}/*/ 2>/dev/null |
    sort -k 2 -t '-'
}

function checkBgo() {
  if ! bugz -h >/dev/null; then
    echo "pybugz is b0rken" >&2
    return 1
  fi

  if ! bugz -q get 2 >/dev/null; then
    echo "b.g.o cannot be queried" >&2
    return 1
  fi
}

# transform the title into space separated search items + set few common vars
function createSearchString() {
  # no local here
  # shellcheck disable=SC2154
  bugz_search=$issuedir/bugz_search
  bugz_result=$issuedir/bugz_result

  for f in $bugz_search $bugz_result; do
    if [[ ! -f $f ]]; then
      truncate -s 0 $f
      chmod a+w $f
    fi
  done

  sed -e 's,^.* - ,,' \
    -e 's,/\.\.\./, ,' \
    -e 's,[\(\)], ,g' \
    -e 's,\s\s*, ,g' \
    $issuedir/title >$bugz_search
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
  grep -q -e "^Traceback" -e "# Error: Bugzilla error:" $bugz_result
}

function GotResults() {
  [[ -s $bugz_result ]]
}

function SearchForSameIssue() {
  if grep -q 'file collision with' $issuedir/title; then
    collision_partner=$(sed -e 's,.*file collision with ,,' $issuedir/title)
    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    # shellcheck disable=SC2154
    $__tinderbox_bugz_timeout bugz -q --columns 400 search --show-status -- "file collision $pkgname $collision_partner_pkgname" |
      grep -e " UNCONFIRMED " -e " CONFIRMED " -e " IN_PROGRESS " |
      sort -n -r |
      head -n 4 |
      tee $bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi

  else
    # shellcheck disable=SC2154
    for i in $pkg $pkgname; do
      $__tinderbox_bugz_timeout bugz -q --columns 400 search --show-status -- $i "$(cat $bugz_search)" |
        grep -e " UNCONFIRMED " -e " CONFIRMED " -e " IN_PROGRESS " |
        sort -n -r |
        head -n 4 |
        tee $bugz_result
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
  # resolved does not fit "same issue"
  for i in $pkg $pkgname; do
    $__tinderbox_bugz_timeout bugz -q --columns 400 search --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(cat $bugz_search)" |
      sort -n -r |
      head -n 3 |
      tee $bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      echo -e " \n^^ DUPLICATE\n"
      return 0
    fi

    $__tinderbox_bugz_timeout bugz -q --columns 400 search --show-status --status RESOLVED -- $i "$(cat $bugz_search)" |
      sort -n -r |
      head -n 3 |
      tee $bugz_result
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
  $__tinderbox_bugz_timeout bugz -q --columns 400 search --show-status $pkgname |
    grep -v -i -E "$g" |
    sort -n -r |
    head -n 12 |
    tee $bugz_result
  if BgoIssue; then
    return 1
  elif GotResults; then
    return 0
  fi

  if [[ $(wc -l <$bugz_result) -lt 5 ]]; then
    echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
    $__tinderbox_bugz_timeout bugz -q --columns 400 search --status RESOLVED $pkgname |
      grep -v -i -E "$g" |
      sort -n -r |
      head -n 5 |
      tee $bugz_result
    if BgoIssue; then
      return 1
    elif GotResults; then
      return 0
    fi
  fi

  return 1
}

# handle bugz/b.g.o. hang
export __tinderbox_bugz_timeout="timeout --signal=15 --kill-after=1m 3m"
