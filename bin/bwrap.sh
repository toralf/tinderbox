#!/bin/bash
#
# set -x


# bubblewrap into an image interactively - or - run an entrypoint script
# https://forums.gentoo.org/viewtopic.php?p=8452922


# avoid oom-killer eg. at emerging dev-perl/GD
# and restrict blast radius if -j1 for make processes is ignored
function cgroup() {

  local sysfsdir="/sys/fs/cgroup/memory/tinderbox-${mnt##*/}"
  if [[ ! -d "$sysfsdir" ]]; then
    mkdir -p "$sysfsdir"
  elif [[ $(wc -l < "$sysfsdir/tasks") -gt 0 ]]; then
    echo " cgroup memory has pid(s)"
    exit 1
  fi

  echo "$$" > "$sysfsdir/tasks"

  echo "16G" > $sysfsdir/memory.limit_in_bytes
  echo "24G" > $sysfsdir/memory.memsw.limit_in_bytes

  local sysfsdir="/sys/fs/cgroup/cpu/tinderbox-${mnt##*/}"
  if [[ ! -d "$sysfsdir" ]]; then
    mkdir -p "$sysfsdir"
  elif [[ $(wc -l < "$sysfsdir/tasks") -gt 0 ]]; then
    echo " cgroup cpu has pid(s)"
    exit 1
  fi

  echo "$$" > "$sysfsdir/tasks"

  echo "100000" > $sysfsdir/cpu.cfs_quota_us
  echo "100000" > $sysfsdir/cpu.cfs_period_us
}


function UnlockAndExit()  {
  rm "$lock"
  exit ${1:-1}
}


function Exit()  {
  exit ${1:-1}
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8

trap Exit QUIT TERM

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root"
  exit 1
fi

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo " wrong # of args"
  exit 1
fi

if [[ "$1" =~ ".." || "$1" =~ "//" || "$1" =~ [[:space:]] || "$1" =~ '\' ]]; then
  echo "illegal character(s) in $1"
  exit 2
fi

if [[ -d /home/tinderbox/img1/"${1##*/}" ]]; then
  mnt=/home/tinderbox/img1/"${1##*/}"

elif [[ -d /home/tinderbox/img2/"${1##*/}" ]]; then
  mnt=/home/tinderbox/img2/"${1##*/}"

else
  echo "no valid mount point found for $1"
  exit 2
fi

if [[ "$mnt" = "/home/tinderbox/img1/" || "$mnt" = "/home/tinderbox/img2/" || ! -d "$mnt" || -L "$mnt" || $(stat -c '%u' "$mnt") -ne 0 ]]; then
  echo "mount point not accepted"
  exit 2
fi

# 1st barrier to prevent to run emerge at the same image twice
lock="$mnt/var/tmp/tb/LOCK"
if [[ -f "$lock" || -L "$lock" ]]; then
  echo "found lock $lock"
  exit 3
fi
touch "$lock"
if [[ -L "$lock" ]]; then
  echo "found symlinked lock $lock"
  exit 3
fi
chown tinderbox:tinderbox "$lock"

# 2nd barrier
pgrep -af "^/usr/bin/bwrap --bind /home/tinderbox/img[12]/$(echo ${mnt##*/} | sed 's,+,.,g')" && exit 3

# 3rd barrier
cgroup

# if now an error occurred then it is safe to remove the lock
trap UnlockAndExit QUIT TERM

rm -f "$mnt/entrypoint"
if [[ $# -eq 2 ]]; then
  if [[ -f "$2" ]]; then
    touch     "$mnt/entrypoint"
    chmod 744 "$mnt/entrypoint"
    cp "$2"   "$mnt/entrypoint"
  else
    echo "no valid entry point script given: $2"
    exit 4
  fi
fi

sandbox=(env -i
    PATH=/usr/sbin:/usr/bin:/sbin:/bin
    HOME=/root
    SHELL=/bin/bash
    TERM=linux
    /usr/bin/bwrap
    --bind "$mnt"                       /
    --bind /home/tinderbox/tb/data      /mnt/tb/data
    --bind /home/tinderbox/distfiles    /var/cache/distfiles
    --ro-bind /home/tinderbox/tb/sdata  /mnt/tb/sdata
    --ro-bind /var/db/repos             /mnt/repos
    --tmpfs                             /var/tmp/portage
    --tmpfs /dev/shm
    --dev /dev --proc /proc
    --mqueue /dev/mqueue
    --unshare-ipc --unshare-pid --unshare-uts
    --hostname "BWRAP-$(echo "${mnt##*/}" | sed -e 's,[+\.],_,g' | cut -c-57)"
    --chdir /
    --die-with-parent
     /bin/bash -l
)

if [[ -x "$mnt/entrypoint" ]]; then
  ("${sandbox[@]}" -c "chmod 1777 /dev/shm && /entrypoint")
else
  ("${sandbox[@]}")
fi

UnlockAndExit $?
