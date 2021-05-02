function __list_images() {
  (
    ls ~tinderbox/run/
    ls /run/tinderbox/ | sed 's,.lock,,g'
  ) |\
  sort -u |\
  while read -r i
  do
    ls -d ~tinderbox/img{1,2}/${i} 2>/dev/null
  done |\
  sort -k 5 -t'/'
}


function __dice() {
  local n=$1
  local N=$2
  [[ $(($RANDOM % N)) -lt $n ]]
}


function __is_running() {
  [[ -d "/run/tinderbox/${1##*/}.lock" ]]
}
