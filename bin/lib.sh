# if locked or symlinked to ~run
function __list_images() {
  (
    ls ~/run/                    | sort
    ls /run/tinderbox/ | sed 's,.lock,,g' | sort
  ) |\
  xargs -n 1 --no-run-if-empty basename  |\
  awk '!x[$0]++' |\
  while read -r i
  do
    ls -d ~/run/${i} 2>/dev/null ||\
    ls -d ~/img/${i} 2>/dev/null
  done |\
  cat
}


# n:N, eg. 1:5
function __dice() {
  local n=$1
  local N=$2
  [[ $(($RANDOM % N)) -lt $n ]]
}


# lock dir is handled by bwrap and cgroup agent
function __is_running() {
  [[ -d "/run/tinderbox/${1##*/}.lock" ]]
}


# timestamp, prefer creation time of symlink
function getStartTime() {
  local image=$1

  local f=~/run/$(basename $image)
  if [[ -e $f ]]; then
    stat -c%Y $f
  else
    stat -c%Y $image
  fi
}

