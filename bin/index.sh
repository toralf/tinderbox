#!/bin/bash
# set -x

# create ~tinderbox/img/index.html


function listStat()  {
  date >> $tmpfile
  echo -e "<h2>few stats</h2>\n<pre>" >> $tmpfile
  echo "<h3>coverage</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -c | recode --silent ascii..html >> $tmpfile
  (cd  ~tinderbox/img; ls packages.*.*covered.txt needed*.txt 2>/dev/null) | recode --silent ascii..html | xargs --no-run-if-empty -I{} echo '<a href="./{}">{}</a>' >> $tmpfile
  echo "<h3>overview</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -o | recode --silent ascii..html >> $tmpfile
  echo "<h3>packages per day per image</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -d | recode --silent ascii..html >> $tmpfile
  echo "<h3>packages per hour</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -e | recode --silent ascii..html >> $tmpfile
  echo "<h3>current task per image</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -t | recode --silent ascii..html >> $tmpfile
  echo "<h3>current emerge per image</h3>" >> $tmpfile
  $(dirname $0)/whatsup.sh -l | recode --silent ascii..html >> $tmpfile
  echo -e "\n</pre>\n" >> $tmpfile
}


function listImages()  {
  echo -e "<h2>content of directory ~tinderbox/img</h2>\nHint: Tinderbox data are under ./var/tmp/tb\n<br>\n<pre>"  >> $tmpfile
  (cd ~tinderbox/img; ls -d 17.* 2>/dev/null) | recode --silent ascii..html | xargs --no-run-if-empty -I{} echo '<a href="./{}">{}</a>' >> $tmpfile
  echo -e "</pre>\n" >> $tmpfile
}


function listBugs() {
  cat << EOF >> $tmpfile
<h2>reported <a href="https://bugs.gentoo.org/">Gentoo Bugs</a> of images in ~tinderbox/img </h2>

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
      <th>Issue</th>
    </tr>
  </tfoot>

  <tbody>

EOF

  ls -t ~tinderbox/img/*/var/tmp/tb/issues/*/.reported 2>/dev/null |\
  while read -r f
  do
    buguri=$(cat $f 2>/dev/null) || continue    # race with house keeping
    bugno=$(cut -f2 -d'=' <<< $buguri)
    d=${f%/*}
    ftitle=$d/title
    image=$(cut -f5 -d'/' <<< $d)
    cat << EOF >> $tmpfile
    <tr>
      <td><a href="$buguri">$bugno</a></td>
      <td>$(recode --silent ascii..html < $ftitle)</td>
      <td><a href="./$image/">$image</a></td>
      <td><a href="./$image/etc/portage/">link</a></td>
      <td><a href="$(cut -f5- -d'/' <<< $d)/">link</a></td>
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
listImages
listBugs
echo -e "\n</html>\n" >> $tmpfile

cp $tmpfile ~tinderbox/img/index.html
rm $tmpfile
