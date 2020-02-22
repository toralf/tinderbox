#!/bin/bash
#
# set -x

export LANG=C

# chroot into an image either interactively -or- run a command

function mountall() {
  # if a mount fails then do not try further
  #
  /bin/mount -t proc       proc        $mnt/proc   &&\
  /bin/mount --rbind       /sys        $mnt/sys    &&\
  /bin/mount --make-rslave             $mnt/sys    &&\
  /bin/mount --rbind       /dev        $mnt/dev    &&\
  /bin/mount --make-rslave             $mnt/dev    &&\
  #
  /bin/mount -o bind      ~tinderbox/tb/data  $mnt/mnt/tb/data    &&\
  /bin/mount -o bind      ~tinderbox/tb/sdata $mnt/mnt/tb/sdata   &&\
  #
  /bin/mount -o bind,ro   /var/db/repos         $mnt/mnt/repos            &&\
  /bin/mount -t tmpfs     tmpfs -o size=16G     $mnt/var/tmp/portage      &&\
  /bin/mount -o bind      ~tinderbox/distfiles  $mnt/var/cache/distfiles  &&\

  return $?
}


function umountall()  {
#   # umount in the reverse order as much as possible despite errors
  #
  local rc=0

  /bin/umount -l $mnt/var/cache/distfiles     || rc=$?
  /bin/umount -l $mnt/var/tmp/portage         || rc=$?
  /bin/umount -l $mnt/mnt/repos               || rc=$?

  /bin/umount -l $mnt/mnt/tb/{sdata,data}     || rc=$?

  /bin/umount -l $mnt/dev{/pts,/shm,/mqueue,} || rc=$?
  /bin/umount -l $mnt/{sys,proc}              || rc=$?

  if [[ $rc -eq 0 ]]; then
    rm $lock
  fi

  return $rc
}


# CGroup based limitations to avoid oom-killer eg. for dev-perl/GD
# needs:
# CONFIG_MEMCG=y
# CONFIG_MEMCG_SWAP=y
# CONFIG_MEMCG_SWAP_ENABLED=y
function cgroup() {
  local sysfsdir=/sys/fs/cgroup/memory/tinderbox-${mnt##*/}
  if [[ ! -d $sysfsdir ]]; then
    mkdir -p $sysfsdir
  fi

  echo "$$" > $sysfsdir/tasks

  local mbytes=$(echo " 8 * 2^30" | bc)
  echo $mbytes > $sysfsdir/memory.limit_in_bytes

  local vbytes=$(echo "16 * 2^30" | bc)
  echo $vbytes > $sysfsdir/memory.memsw.limit_in_bytes
}


function BailOut()  {
  umountall
  exit 1
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################
trap BailOut QUIT TERM KILL

if [[ "$(whoami)" != "root" ]]; then
  echo " you must be root !"
  exit 1
fi

# the path to the chroot image
#
mnt=$1

if [[ ! -d $mnt ]]; then
  echo "not a valid mount point: '$mnt'"
  exit 1
fi

# treat remaining option/s as the command line to be run
#
shift

# 1st barrier to prevent starting the same chroot image twice
#
lock=$mnt/var/tmp/tb/LOCK
if [[ -f $lock ]]; then
  echo "found lock file $lock"
  exit 1
fi
touch $lock || exit 2
chown tinderbox:tinderbox $lock

# 2nd barrier to prevent running the same image twice
#
grep -m 1 "/${mnt##*/}/" /proc/mounts
if [[ $? -eq 0 ]]; then
  echo "^^^^^ found (stale?) mounts of $mnt"
  exit 3
fi

mountall
if [[ $? -ne 0 ]]; then
  echo "something went wrong during mount!"
  umountall
  exit 4
fi

cgroup

# "su - root" forces the use root's tinderbox image environment
#
if [[ $# -gt 0 ]]; then
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c '$@'"
else
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root"
fi
rc=$?

umountall
if [[ $? -ne 0 ]]; then
  echo "something went wrong during umount, previous rc was: $rc"
  exit 5
fi

exit $rc
