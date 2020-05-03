#!/bin/bash
#
# set -x

# this is a (s)imple (c)hroot (w)rapper into a tinderbox image

set -euf
export PATH="/usr/sbin:/usr/bin:/sbin:/bin:/opt/tb/bin"
export LANG=C.utf8


if [[ $# -lt 1 ]]; then
  echo " wrong opt(s)!"
  exit 1
fi

mnt="$(ls -d ~tinderbox/img{1,2}/${1##*/} 2>/dev/null || true)"

if [[ ! -d "$mnt" ]]; then
  echo "not a valid mount point: '$mnt'"
  exit 1
fi

# remaining options are treated as a complete command line to be run within chroot
#
shift

# do "su - root" to source root's tinderbox image environment
#
if [[ $# -gt 0 ]]; then
  /usr/bin/chroot "$mnt" /bin/bash -l -c "su - root -c '${@}'"
else
  /usr/bin/chroot "$mnt" /bin/bash -l -c "su - root"
fi

exit 0
