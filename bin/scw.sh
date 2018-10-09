#!/bin/bash
#
# set -x

# this is a (s)imple (c)hroot (w)rapper into a (maybe running) tinderbox image

mnt=$1

if [[ ! -d $mnt ]]; then
  echo "not a valid mount point: '$mnt'"
  exit 1
fi

# remaining options are treated as a complete command line to be run within chroot
#
shift

# do "su - root" to use root's tinderbox image environment
#
if [[ $# -gt 0 ]]; then
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c '$@'"
else
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root"
fi

exit $?
