# SPDX-License-Identifier: GPL-3.0-or-later

function __getStartTime() {
  cat ~tinderbox/img/$(basename $1)/var/tmp/tb/setup.timestamp
}


function __is_cgrouped() {
  [[ -d /sys/fs/cgroup/cpu/local/$(basename $1)/ ]]
}


function __is_locked() {
  [[ -d /run/tinderbox/$(basename $1).lock/ ]]
}


function __is_running() {
  __is_cgrouped $1 || __is_locked $1
}


function checkBgo() {
  if ! bugz -h 1>/dev/null; then
    echo "www-client/pybugz installation is b0rken" >&2
    return 1

  elif ! bugz -q get 2 1>/dev/null; then
    { echo "b.g.o is down"; } >&2
    return 2
  fi
}


# transform the title into space separated search items + set few common vars
function createSearchString() {
  # no local here
  bugz_search=$issuedir/bugz_search
  bugz_result=$issuedir/bugz_result

  for f in $bugz_search $bugz_result
  do
    if [[ ! -f $f ]]; then
      truncate -s 0 $f
      chmod a+rw    $f
    fi
  done

  sed -e 's,^.* - ,,'     \
      -e 's,/\.\.\./, ,'  \
      -e 's,[\(\)], ,g'   \
      -e 's,\s\s*, ,g'    \
      $issuedir/title > $bugz_search
}


# look for a blocker bug id
# the BLOCKER file contains tupels like:
#
#   # comment
#   <bug id>
#   <pattern/s>
function LookupForABlocker() {
  local pattern_file=$1

  while read -r line
  do
    if [[ $line =~ ^[0-9]+$ ]]; then
      read -r number <<< $line
      continue
    fi

    if grep -q -E "$line" $issuedir/title; then
      echo $number
      return
    fi
  done < <(grep -v -e '^#' -e '^$' $pattern_file)

  if [[ -f $issuedir/files/clang.tar.bz2 ]]; then
    echo "870412"
    return
  fi

  return
}


function GotResults() {
  if grep -q -e "^Traceback" -e "# Error: Bugzilla error:" $bugz_result; then
    return 2
  fi
  [[ -s $bugz_result ]]
}


function SearchForSameIssue() {
  if grep -q 'file collision with' $issuedir/title; then
    # for a file collision report both involved sites
    local collision_partner=$(sed -e 's,.*file collision with ,,' < $issuedir/title)

    collision_partner_pkgname=$(qatom -F "%{CATEGORY}/%{PN}" $collision_partner)
    $bugz_timeout bugz -q --columns 400 search --show-status -- "file collision $pkgname $collision_partner_pkgname" |
        grep -e " CONFIRMED " -e " IN_PROGRESS " |
        sort -n -r |
        head -n 4 |
        tee $bugz_result
    if GotResults; then
      return 0
    elif [[ $? -eq 2 ]]; then
      return 2
    fi
  fi

  for i in $pkg $pkgname
  do
    $bugz_timeout bugz -q --columns 400 search --show-status -- $i "$(cat $bugz_search)" |
        grep -e " CONFIRMED " -e " IN_PROGRESS " |
        sort -n -r |
        head -n 4 |
        tee $bugz_result
    if GotResults; then
      return 0
    elif [[ $? -eq 2 ]]; then
      return 2
    fi
  done

  return 1
}


function SearchForSimilarIssue() {
  # resolved does not fit "same issue"
  for i in $pkg $pkgname
  do
    $bugz_timeout bugz -q --columns 400 search --show-status --status RESOLVED --resolution DUPLICATE -- $i "$(cat $bugz_search)" |
        sort -n -r |
        head -n 3 |
        tee $bugz_result
    if GotResults; then
      echo -e " \n^^ DUPLICATE\n"
      return 0
    elif [[ $? -eq 2 ]]; then
      return 2
    fi

    $bugz_timeout bugz -q --columns 400 search --show-status --status RESOLVED -- $i "$(cat $bugz_search)" |
        sort -n -r |
        head -n 3 |
        tee $bugz_result
    if GotResults; then
      return 0
    elif [[ $? -eq 2 ]]; then
      return 2
    fi
  done

  # now search without version/revision

  local h='https://bugs.gentoo.org/buglist.cgi?query_format=advanced&short_desc_type=allwordssubstr'
  local g='stabilize|Bump| keyword| bump'

  echo -e "OPEN:     $h&resolution=---&short_desc=$pkgname\n"
  $bugz_timeout bugz -q --columns 400 search --show-status $pkgname |
      grep -v -i -E "$g" |
      sort -n -r |
      head -n 12 |
      tee $bugz_result
  if GotResults; then
    return 0
  elif [[ $? -eq 2 ]]; then
    return 2
  fi

  if [[ $(wc -l < $bugz_result) -lt 5 ]]; then
    echo -e "\nRESOLVED: $h&bug_status=RESOLVED&short_desc=$pkgname\n"
    $bugz_timeout bugz -q --columns 400 search --status RESOLVED $pkgname |
        grep -v -i -E "$g" |
        sort -n -r |
        head -n 5 |
        tee $bugz_result
    if GotResults; then
      return 0
    elif [[ $? -eq 2 ]]; then
      return 2
    fi
  fi

  return 1
}


export bugz_timeout="timeout --signal=15 --kill-after=1m 3m"   # bugz tends to hang
