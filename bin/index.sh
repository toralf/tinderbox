#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
# set -x

# create the index file ~tinderbox/img/index.html


function listStat()  {
  date >> $tmpfile
  echo "<h2>few stats</h2>" >> $tmpfile
  echo "<pre>" >> $tmpfile
  echo "<h3>coverage</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -c | recode --silent ascii..html >> $tmpfile
  echo "<h3>overview</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -o | recode --silent ascii..html >> $tmpfile
  echo "<h3>packages per day</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -d | recode --silent ascii..html >> $tmpfile
  echo "<h3>packages per hour</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -e | recode --silent ascii..html >> $tmpfile
  echo "<h3>current task</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -t | recode --silent ascii..html >> $tmpfile
  echo "<h3>current package</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -l | recode --silent ascii..html >> $tmpfile
  echo -e "\n</pre>\n" >> $tmpfile
}


function listFiles()  {
  echo "<h2>downloadable files</h2>" >> $tmpfile
  echo "<pre>" >> $tmpfile
  (cd ~tinderbox/img; find . -maxdepth 1 -type f) | recode --silent ascii..html |
  xargs --no-run-if-empty -I{} echo '<a href="./{}">{}</a>' >> $tmpfile
  echo -e "\n</pre>\n" >> $tmpfile
}


function listBugs() {
  cat << EOF >> $tmpfile
<h2><a href="https://bugs.gentoo.org/">Gentoo Bugs</a> and links to inspect the image content</h2>

<table border="0" align="left" class="list_table">

  <thead align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>/</th>
      <th>/etc/portage/</th>
      <th>IssueDir</th>
    </tr>
  </thead>

  <tfoot align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>/</th>
      <th>/etc/portage</th>
      <th>IssueDir</th>
    </tr>
  </tfoot>

  <tbody>

EOF

  ls -t -- ~tinderbox/img/*/var/tmp/tb/issues/*/.reported 2>/dev/null |
  while read -r f
  do
    uri=$(cat $f 2>/dev/null) || continue    # race with house keeping
    no=$(cut -f2 -d'=' <<< $uri)
    d=${f%/*}
    title=$d/title
    image=$(cut -f5 -d'/' <<< $d)
    cat << EOF >> $tmpfile
    <tr>
      <td><a href="$uri">$no</a></td>
      <td>$(recode --silent ascii..html < $title)</td>
      <td><a href="./$image/">$image</a></td>
      <td><a href="./$image/etc/portage/">portage</a></td>
      <td><a href="$(cut -f5- -d'/' <<< $d)/">issue</a></td>
    </tr>
EOF

  done

  echo -e "  </tbody>\n</table>\n" >> $tmpfile
}


#######################################################################
set -eu
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

cat << EOF > ~tinderbox/img/robots.txt
User-agent: *
Disallow: /

EOF

tmpfile=$(mktemp /tmp/$(basename $0)_XXXXXX.tmp)
cat << EOF >> $tmpfile
<html>

<h1>recent <a href="https://zwiebeltoralf.de/tinderbox.html">tinderbox</a> data</h1>

EOF
listStat
listFiles
listBugs
echo -e "\n</html>\n" >> $tmpfile

cp $tmpfile ~tinderbox/img/index.html
rm $tmpfile
