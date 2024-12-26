#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# create the index file ~tinderbox/img/index.html

function listStat() {
  {
    date
    echo '<h2>few stats</h2>'
    echo '<pre>'
    echo '<h3>coverage</h3>'
    $(dirname $0)/whatsup.sh -c | recode --silent ascii..html
    echo '<h3>packages per image per run day</h3>'
    $(dirname $0)/whatsup.sh -d | recode --silent ascii..html
    echo '<h3>stats about completed and failed packages, reported bugs at b.g.o., back logs, lock status</h3>'
    $(dirname $0)/whatsup.sh -o | recode --silent ascii..html
    echo '<h3>current task</h3>'
    $(dirname $0)/whatsup.sh -t | recode --silent ascii..html
    echo '<h3>current emerge step</h3>'
    $(dirname $0)/whatsup.sh -l | recode --silent ascii..html
    echo -e '</pre>\n'
  }
}

function listFiles() {
  local files=$(
    find ~tinderbox/img/ -maxdepth 1 -type f -print0 |
      xargs -r -n 1 --null basename |
      sort |
      while read -r f; do
        echo $f
      done
  )
  local n=$(wc -w <<<$files)
  {
    echo "<h2>$n files for gentoo devs</h2>"
    echo "<pre>"
    for f in $files; do
      echo "<a href=\"$f\">$f ($(ls -lh ~tinderbox/img/$f 2>/dev/null | awk '{ print $5 }'))</a>"
    done
    echo -e "</pre>\n"
  }
}

function listImagesWithoutAnyBug() {
  local dirs=$(
    find ~tinderbox/img/ -maxdepth 1 -type d -name '23*' -print0 |
      xargs -r -n 1 --null basename |
      sort |
      while read -r d; do
        if [[ ! -d ~tinderbox/img/$d/var/tmp/tb/issues ]]; then
          echo $d
        fi
      done
  )
  local n=$(wc -w <<<$dirs)
  {
    echo "<h2>$n images with no bug</h2>"
    echo "<pre>"
    for d in $dirs; do
      echo "<a href=\"$d\">$d</a>"
    done
    echo -e "</pre>\n"
  }
}

function listImagesWithoutReportedBugs() {
  local dirs=$(
    find ~tinderbox/img/ -maxdepth 1 -type d -name '23*' -print0 |
      xargs -r -n 1 --null basename |
      sort |
      while read -r d; do
        if [[ -d ~tinderbox/img/$d/var/tmp/tb/issues ]] && ! ls ~tinderbox/img/$d/var/tmp/tb/issues/*/.reported &>/dev/null; then
          echo $d
        fi
      done
  )
  local n=$(wc -w <<<$dirs)
  {
    echo "<h2>$n images with no reported bug</h2>"
    echo "<pre>"
    for d in $dirs; do
      echo "<a href=\"$d\">$d</a>"
    done
    echo -e "</pre>\n"
  }
}

function listBugs() {
  local files=$(ls -t -- ~tinderbox/img/*/var/tmp/tb/issues/*/.reported 2>/dev/null)
  local n=$(sed -e 's,/var/tmp/tb/issues.*,,' <<<$files | sort -u | wc -l)

  cat <<EOF
<h2>$n images with $(wc -l <<<$files) reported bugs in total (<a href="https://bugs.gentoo.org/buglist.cgi?columnlist=assigned_to%2Cbug_status%2Cresolution%2Cshort_desc%2Copendate&email1=toralf%40gentoo.org&emailassigned_to1=1&emailreporter1=1&emailtype1=substring&known_name=all%20my%20bugs&limit=0&list_id=7234723&order=opendate%20DESC%2Cbug_id&query_format=advanced&remtype=asdefault&resolution=---">all reported, open bugs at b.g.o.</a>)</h2>

  <table border="0" align="left" class="list_table" width="100%">

  <thead align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>Image /</th>
      <th>Artifacts</th>
    </tr>
  </thead>

  <tfoot align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>Image /</th>
      <th>Artifacts</th>
    </tr>
  </tfoot>
  <tbody>
EOF

  while read -r f; do
    local uri=$(cat $f 2>/dev/null) # b.g.o. link
    local no=${uri##*/}             # bug number
    if [[ -z $no ]]; then
      continue # race with house keeping
    fi

    # f: /home/tinderbox/img/23.0_llvm-20241010-060009/var/tmp/tb/issues/20241013-122040-dev-db_myodbc-8.0.32/.reported
    local d=${f%/*}

    # d: /home/tinderbox/img/23.0_llvm-20241010-060009/var/tmp/tb/issues/20241013-122040-dev-db_myodbc-8.0.32
    local issuedir=$(cut -f 5- -d '/' <<<$d)

    # issuedir: 23.0_llvm-20241010-060009/var/tmp/tb/issues/20241013-122040-dev-db_myodbc-8.0.32
    local image=${issuedir%%/*}

    local pkg=${d##*/}

    cat <<EOF
  <tr>
    <td><a href="$uri">$no</a></td>
    <td>$(cut -c -$__tinderbox_bugz_title_length <$d/title | recode --silent ascii..html)</td>
    <td><a href="./$image/">$image</a></td>
    <td><a href="./$issuedir/">$pkg</a></td>
  </tr>
EOF
  done <<<$files

  cat <<EOF
  </tbody>
  </table>
EOF
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

source $(dirname $0)/lib.sh

if [[ ! -s ~tinderbox/img/robots.txt ]]; then
  echo -e "User-agent: *\nDisallow: /\n" >~tinderbox/img/robots.txt
fi

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
{
  cat <<EOF
<html>
<head>
  <meta http-equiv="refresh" content="300">
</head>

<body>
<h1>recent <a href="https://zwiebeltoralf.de/tinderbox.html">tinderbox</a> data</h1>
EOF
  listStat
  listFiles
  listImagesWithoutAnyBug
  listImagesWithoutReportedBugs
  listBugs
  cat <<EOF
</body>
</html>
EOF
} >>$tmpfile

# we're not root, so mv doesn't work
cp $tmpfile ~tinderbox/img/index.html
rm $tmpfile
