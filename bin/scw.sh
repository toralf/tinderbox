# #!/bin/sh
#
# set -x

# this is a (s)imple (c)hroot (w)rapper to chroot into a *running* tinderbox image
# it will not mount any file systems like /dev, /proc or so

if [[ $# -eq 0 ]]; then
  echo
  echo " an image name is expected !"
  echo
  exit 1
fi

mnt=$1
shift

# guess a directory if just the name is given
#
if [[ ! -d $mnt ]]; then
  tmp=$(ls -d /home/tinderbox/img?/$mnt 2>/dev/null)
  if [[ ! -d $tmp ]]; then
    echo
    echo " cannot guess the full path to the image $mnt"
    echo
    exit 1
  fi

  mnt=$tmp
fi

if [[ $# -gt 0 ]]; then
  # do "su - root" to double ensure to use the chroot image environment
  #
  /usr/bin/chroot $mnt /bin/bash -l -c "su - root -c '$@'"
else
  /usr/bin/chroot $mnt /bin/bash -l
fi

exit $?
