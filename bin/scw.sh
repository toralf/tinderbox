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

if [[ $# -gt 0 ]]; then
  # do "su - root" to double ensure to use the chroot image environment
  #
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c '$@'"
else
  /usr/bin/chroot $mnt /bin/bash -l
fi

exit $?
