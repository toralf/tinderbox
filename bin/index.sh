#!/bin/bash
# set -x

# create ~tinderbox/img/index.html from .reported file in issues directory

index=~tinderbox/img/index.html

truncate -s 0 $index

cat << EOF >> $index
<html>

<h1>The current <a href="https://zwiebeltoralf.de/tinderbox.html">tinderbox</a> results.</h1>

<table border="0" align="left">
  <thead align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>Image</th>
    </tr>
  </thead>

  <tfoot align="left">
    <tr>
      <th>Bug</th>
      <th>Title</th>
      <th>Image</th>
    </tr>
  </tfoot>

  <tbody align="left">
EOF

ls -t ~tinderbox/img/*/var/tmp/tb/issues/*/.reported |\
while read -r f
do
  buguri=$(cat $f)
  bugno=$(cut -f2 -d'=' <<< $buguri)
  d=$(dirname $f)
  ftitle=$d/title
  image=$(cut -f5 -d'/' <<< $d)
  cat << EOF >> $index
    <tr>
      <td><a href="$buguri">$bugno</a></td>
      <td>$(cat $ftitle)</td>
      <td><a href="./$image">$image</a></td>
    </tr>
EOF

done

cat << EOF >> $index
  </tbody>
</table>

</html>

EOF
