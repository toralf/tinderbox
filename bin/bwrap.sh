#!/bin/bash
#
# set -x

# bubblewrap into an image interactively - or - run a command

function cgroup() {
  # avoid oom-killer eg. while emerging dev-perl/GD
  #
  local sysfsdir=/sys/fs/cgroup/memory/tinderbox-${mnt##*/}
  if [[ ! -d $sysfsdir ]]; then
    mkdir -p $sysfsdir
  fi

  echo "$$" > $sysfsdir/tasks

  local mbytes=$(echo "12 * 2^30" | bc)
  echo $mbytes > $sysfsdir/memory.limit_in_bytes

  local vbytes=$(echo "16 * 2^30" | bc)
  echo $vbytes > $sysfsdir/memory.memsw.limit_in_bytes

  # restrict blast radius if -j1 for make processes is ignored
  #
  local sysfsdir=/sys/fs/cgroup/cpu/tinderbox-${mnt##*/}
  if [[ ! -d $sysfsdir ]]; then
    mkdir -p $sysfsdir
  fi

  echo "$$" > $sysfsdir/tasks

  echo "100000" > $sysfsdir/cpu.cfs_quota_us
  echo "100000" > $sysfsdir/cpu.cfs_period_us
}


function Exit()  {
  rm $lock
  exit ${1:-1}
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
trap Exit QUIT TERM KILL
set -uf

export LANG=C.utf8

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# the path to the image
#
mnt=$1

if [[ ! -d $mnt ]]; then
  echo "not a valid mount point: '$mnt'"
  exit 1
fi

# treat remaining option/s as the command line to be run within the image
#
shift

# simple barrier to prevent running the same image twice
#
lock=$mnt/var/tmp/tb/LOCK
if [[ -f $lock ]]; then
  echo "found lock file $lock"
  exit 1
fi
touch $lock || exit 2 # no write perms ?!?
chown tinderbox:tinderbox $lock

cgroup

sandbox="/usr/bin/bwrap
    --bind $mnt                         /
    --bind /home/tinderbox/tb/data      /mnt/tb/data
    --bind /home/tinderbox/distfiles    /var/cache/distfiles
    --ro-bind /home/tinderbox/tb/sdata  /mnt/tb/sdata
    --ro-bind /var/db/repos             /mnt/repos
    --tmpfs                             /var/tmp/portage
    --tmpfs /dev/shm
    --dev /dev --proc /proc
    --mqueue /dev/mqueue
    --unshare-ipc --unshare-pid --unshare-uts
    --hostname BWRAP-$(basename $mnt | sed -e 's,[\.],_,g' | cut -c-57)
    --chdir /
    --die-with-parent
     /bin/bash -l
"

if [[ $# -gt 0 ]]; then
  $sandbox -c "chmod 1777 /dev/shm && ${@}"
else
  $sandbox
fi

Exit $?
