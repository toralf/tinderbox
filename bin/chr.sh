#!/bin/sh
#
#set -x

# chroot into an image either interactively -or- run a command and exit afterwards
#
# typical call:
#
# $> sudo /opt/tb/bin/chr.sh ~/run/plasma-unstable_20150811-144142

# if a mount fails then bail out immediately
#
function mountall() {

  # system dirs
  #
  /bin/mount -t proc       proc        $mnt/proc   &&\
  /bin/mount --rbind       /sys        $mnt/sys    &&\
  /bin/mount --make-rslave $mnt/sys                &&\
  /bin/mount --rbind       /dev        $mnt/dev    &&\
  /bin/mount --make-rslave $mnt/dev                &&\
  # portage and tinderbox
  #
  /bin/mount -o bind       /home/tinderbox/tb  $mnt/tmp/tb             &&\
  /bin/mount -o bind,ro    /usr/portage        $mnt/usr/portage        &&\
  /bin/mount -t tmpfs      tmpfs -o size=16G   $mnt/var/tmp/portage    &&\
  /bin/mount -o bind       /var/tmp/distfiles  $mnt/var/tmp/distfiles

  return $?
}


# if an umount fails then try to umount as much as possible
#
function umountall()  {
  rc=0

  /bin/umount -l $mnt/dev{/pts,/shm,/mqueue,}     || rc=$?
  /bin/umount -l $mnt/{sys,proc}                  || rc=$?

  /bin/umount    $mnt/tmp/tb                      || rc=$?
  /bin/umount    $mnt/usr/portage                 || rc=$?
  /bin/umount -l $mnt/var/tmp/{distfiles,portage} || rc=$?

  return $rc
}


#############################################################################
#                                                                           #
# main                                                                      #
#                                                                           #
#############################################################################

# the path to the chroot image
#
mnt=$1

# remaining options are treated as a complete command line to be run within chroot
#
shift

if [[ ! -d "$mnt" ]]; then
  echo
  echo " error: NOT a valid dir: $mnt"
  echo

  exit 1
fi

# 1st barrier to prevent starting a chroot image twice: a lock file
#
lock=$mnt/tmp/LOCK
if [[ -f $lock ]]; then
  echo "found lock file $lock"
  exit 1
fi
touch $lock || exit 2

# 2nd barrier to prevent starting a chroot image twice: grep mount table
# this is a weak condition b/c a mount can be made using a symlink name
#
grep -m 1 "$(basename $mnt)" /proc/mounts && exit 3

# ok, mount now the directories from the host
#
mountall || exit 4

# limit the memory to 16 GB to avoid an oom-killer (eg.: dev-perl/GD)
#
sysfsdir=/sys/fs/cgroup/memory/tinderbox-$(basename $mnt)
if [[ ! -d $sysfsdir ]]; then
  mkdir -p $sysfsdir
  echo "$(echo "16 * 2^30" | bc)" > $sysfsdir/memory.limit_in_bytes
fi
echo "$$" > $sysfsdir/tasks

if [[ $# -gt 0 ]]; then
  # enforce a login of user root b/c then its environment is sourced
  #
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c '$@'"
else
  /usr/bin/chroot $mnt /bin/bash -l
fi
rc1=$?

umountall
rc2=$?

if [[ $rc2 -eq 0 ]]; then
  rm $lock
fi

let "rc = $rc1 + $rc2"

exit $rc
