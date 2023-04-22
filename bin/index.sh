#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# create the index file ~tinderbox/img/index.html

function listStat() {
  {
    date
    echo "<h2>few stats</h2>" >>$tmpfile
    echo -e "\n<pre>\n"
    echo "<h3>coverage</h3>"
    $(dirname $0)/whatsup.sh -c | recode --silent ascii..html
    echo "<h3>overview</h3>"
    $(dirname $0)/whatsup.sh -o | recode --silent ascii..html
    echo "<h3>packages per day</h3>"
    $(dirname $0)/whatsup.sh -d | recode --silent ascii..html
    echo "<h3>packages per hour</h3>"
    $(dirname $0)/whatsup.sh -e | recode --silent ascii..html
    echo "<h3>current task</h3>"
    $(dirname $0)/whatsup.sh -t | recode --silent ascii..html
    echo "<h3>current package</h3>"
    $(dirname $0)/whatsup.sh -l | recode --silent ascii..html
    echo -e "</pre>\n"
  } >>$tmpfile
}

function listFiles() {
  {
    echo "<h2>downloadable files</h2>"
    echo "<pre>"
    (
      cd ~tinderbox/img
      find . -maxdepth 1 -type f
    ) | recode --silent ascii..html |
      xargs --no-run-if-empty -I{} echo '<a href="./{}">{}</a>'
    echo -e "</pre>\n"
  } >>$tmpfile
}

function listBugs() {
  local files=$(ls -t -- ~tinderbox/img/*/var/tmp/tb/issues/*/.reported 2>/dev/null)

  cat <<EOF >>$tmpfile
<h2>links to the last $(wc -l <<<$files) discovered new <a href="https://bugs.gentoo.org/">bugs</a></h2>

  <table border="0" align="left" class="list_table">

  <thead align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>/</th>
      <th>IssueDir</th>
    </tr>
  </thead>

  <tfoot align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>/</th>
      <th>IssueDir</th>
    </tr>
  </tfoot>

  <tbody>
EOF

  while read -r f; do
    uri=$(cat $f 2>/dev/null) || continue # race with house keeping
    no=${uri##*/}
    d=${f%/*}
    title=$d/title
    imagedir=$(cut -f5- -d'/' <<<$d)
    image=${imagedir%%/*}
    pkg=${d##*/}
    cat <<EOF >>$tmpfile
  <tr>
    <td><a href="$uri">$no</a></td>
    <td>$(recode --silent ascii..html <$title)</td>
    <td><a href="./$image/">$image</a></td>
    <td><a href="$imagedir/">$pkg</a></td>
  </tr>
EOF
  done <<<$files

  echo -e "  </tbody>\n  </table>\n" >>$tmpfile
}

#######################################################################
set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

cat <<EOF >~tinderbox/img/robots.txt
User-agent: *
Disallow: /

EOF

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
cat <<EOF >>$tmpfile
<html>

<h1>recent <a href="https://zwiebeltoralf.de/tinderbox.html">tinderbox</a> data</h1>

EOF
listStat
listFiles
listBugs
echo -e "</html>" >>$tmpfile

cp $tmpfile ~tinderbox/img/index.html
rm $tmpfile
