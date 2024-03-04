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
    echo '<h3>stats about completed and failed packages, reported bugs at <a href="https://bugs.gentoo.org/">b.g.o</a> and more</h3>'
    $(dirname $0)/whatsup.sh -o | recode --silent ascii..html
    echo '<h3>current task</h3>'
    $(dirname $0)/whatsup.sh -t | recode --silent ascii..html
    echo '<h3>current emerge step</h3>'
    $(dirname $0)/whatsup.sh -l | recode --silent ascii..html
    echo '<h3>fs</h3>'
    df -h /mnt/data | recode --silent ascii..html
    echo -e '</pre>\n'
  } >>$tmpfile
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
  local n=$(wc -l <<<$files)
  {
    echo "<h2>$n files for gentoo devs</h2>"
    echo "<pre>"
    for f in $files; do
      echo "<a href=\"$f\">$f ($(ls -lh ~tinderbox/img/$f | awk '{ print $5 }'))</a>"
    done
    echo -e "</pre>\n"
  } >>$tmpfile
}

function listImagesWithoutAnyBug() {
  local files=$(
    find ~tinderbox/img/ -maxdepth 1 -type d -name '[12]*' -print0 |
      xargs -r -n 1 --null basename |
      sort |
      while read -r f; do
        if ! ls ~tinderbox/img/$f/var/tmp/tb/issues/* &>/dev/null; then
          echo $f
        fi
      done
  )
  local n=$(wc -l <<<$files)
  {
    echo "<h2>$n images without any bug (too young or b0rken setup)</h2>"
    echo "<pre>"
    for f in $files; do
      echo "<a href=\"$f\">$f</a>"
    done
    echo -e "</pre>\n"
  } >>$tmpfile
}

function listImagesWithoutReportedBugs() {
  local files=$(
    find ~tinderbox/img/ -maxdepth 1 -type d -name '[12]*' -print0 |
      xargs -r -n 1 --null basename |
      sort |
      while read -r f; do
        if ls ~tinderbox/img/$f/var/tmp/tb/issues/* &>/dev/null && ! ls ~tinderbox/img/$f/var/tmp/tb/issues/*/.reported &>/dev/null; then
          echo $f
        fi
      done
  )
  local n=$(wc -l <<<$files)
  {
    echo "<h2>$n images with no reported bug (yet)</h2>"
    echo "<pre>"
    for f in $files; do
      echo "<a href=\"$f\">$f</a>"
    done
    echo -e "</pre>\n"
  } >>$tmpfile
}

function listImagesWithReportedBugs() {
  local files=$(
    find ~tinderbox/img/ -maxdepth 1 -type d -name '[12]*' -print0 |
      xargs -r -n 1 --null basename |
      sort |
      while read -r f; do
        if ls ~tinderbox/img/$f/var/tmp/tb/issues/*/.reported &>/dev/null; then
          echo $f
        fi
      done
  )
  local n=$(wc -l <<<$files)
  {
    echo "<h2>$n images with reported bugs</h2>"
    echo "<pre>"
    for f in $files; do
      echo "<a href=\"$f\">$f</a>"
    done
    echo -e "</pre>\n"
  } >>$tmpfile
}

function listBugs() {
  local files
  files=$(ls -t -- ~tinderbox/img/*/var/tmp/tb/issues/*/.reported 2>/dev/null)

  cat <<EOF >>$tmpfile
<h2>latest $(wc -l <<<$files) reported bugs</h2>

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
    if ! uri=$(cat $f 2>/dev/null); then
      continue # race with house keeping
    fi
    no=${uri##*/}
    if [[ -z $no ]]; then
      continue
    fi
    d=${f%/*}
    issuedir=$(cut -f 5- -d '/' <<<$d)
    image=${issuedir%%/*}
    pkg=${d##*/}
    cat <<EOF >>$tmpfile
  <tr>
    <td><a href="$uri">$no</a></td>
    <td>$(recode --silent ascii..html <$d/title)</td>
    <td><a href="./$image/">$image</a></td>
    <td><a href="$issuedir/">$pkg</a></td>
  </tr>
EOF
  done <<<$files

  cat <<EOF >>$tmpfile
  </tbody>
  </table>
EOF
}

#######################################################################
set -eu
export LANG=C.utf8
export PATH="/usr/sbin:/usr/bin:/sbin:/bin"

echo -e "User-agent: *\nDisallow: /\n" >~tinderbox/img/robots.txt

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
cat <<EOF >>$tmpfile
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
listImagesWithReportedBugs
listBugs
cat <<EOF >>$tmpfile
</body>
</html>
EOF

cp $tmpfile ~tinderbox/img/index.html
rm $tmpfile
