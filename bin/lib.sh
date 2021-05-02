function list_images() {
  (
    ls ~tinderbox/run/
    ls /run/tinderbox/ | sed 's,.lock,,g'
  ) 2>/dev/null |\
  sort -u |\
  while read -r i
  do
    ls -d ~tinderbox/img{1,2}/${i} 2>/dev/null
  done |\
  sort -k 5 -t'/'
}


function dice() {
  local p=$1
  local P=$2
  [[ $(($RANDOM % P)) -lt $p ]]
  return $?
}
