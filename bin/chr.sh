#!/bin/bash
#
# set -x

# chroot into an image either interactively -or- run a command and exit afterwards
#
# typical call:
#
# $> sudo /opt/tb/bin/chr.sh ~/run/plasma-unstable_20150811-144142

# mount the directories shared by the host
#
function mountall() {
  # if a mount fails then bail out immediately
  #

  # system dirs
  #
  /bin/mount -t proc       proc        $mnt/proc   &&\
  /bin/mount --rbind       /sys        $mnt/sys    &&\
  /bin/mount --make-rslave             $mnt/sys    &&\
  /bin/mount --rbind       /dev        $mnt/dev    &&\
  /bin/mount --make-rslave             $mnt/dev    &&\
  #
  # tinderbox data dir
  #
  /bin/mount -o bind      /home/tinderbox/tb  $mnt/tmp/tb             &&\
  #
  # host repo and more
  #
  /bin/mount -o bind,ro   /usr/portage        $mnt/usr/portage        &&\
  /bin/mount -t tmpfs     tmpfs -o size=16G   $mnt/var/tmp/portage    &&\
  /bin/mount -o bind      /var/tmp/distfiles  $mnt/var/tmp/distfiles

  return $?
}


function umountall()  {
  # if an umount fails then try to umount as much as possible
  #
  rc=0

  /bin/umount -l $mnt/dev{/pts,/shm,/mqueue,}     || rc=$?
  /bin/umount -l $mnt/{sys,proc}                  || rc=$?

  /bin/umount    $mnt/tmp/tb                      || rc=$?
  /bin/umount    $mnt/usr/portage                 || rc=$?
  /bin/umount -l $mnt/var/tmp/{distfiles,portage} || rc=$?

  return $rc
}


# CGroup based limitations to avoid oom-killer eg. for dev-perl/GD
# needs:
# CONFIG_MEMCG=y
# CONFIG_MEMCG_SWAP=y
# CONFIG_MEMCG_SWAP_ENABLED=y

function cgroup() {
  sysfsdir=/sys/fs/cgroup/memory/tinderbox-$(basename $mnt)
  if [[ ! -d $sysfsdir ]]; then
    mkdir -p $sysfsdir
  fi

  echo "$$" > $sysfsdir/tasks

  mbytes="$(echo " 8 * 2^30" | bc)"
  echo $mbytes > $sysfsdir/memory.limit_in_bytes

  vbytes="$(echo "16 * 2^30" | bc)"
  echo $vbytes > $sysfsdir/memory.memsw.limit_in_bytes
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################

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

# remaining options is treated as commands to be run within chroot
#
shift

# 1st barrier to prevent starting the same chroot image twice
#
lock=$mnt/tmp/LOCK
if [[ -f $lock ]]; then
  echo "found lock file $lock"
  exit 1
fi
touch $lock || exit 2
chown tinderbox:tinderbox $lock

# 2nd barrier to prevent starting the same chroot image twice
# this is a weak condition b/c a mount could be made using symlink names
#
grep -m 1 "$(basename $mnt)" /proc/mounts && exit 3

mountall || exit 4
cgroup
if [[ $? -eq 0 ]]; then
  if [[ $# -gt 0 ]]; then
    # do "su - root" to double ensure to use root's chroot environment
    #
    /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c '$@'"
  else
    /usr/bin/chroot $mnt /bin/bash -l
  fi
  rc1=$?
fi
umountall
rc2=$?

if [[ $rc2 -eq 0 ]]; then
  rm $lock
else
  echo "rc2=$rc2" >> $lock
fi

let "rc = $rc1 + $rc2"

exit $rc
