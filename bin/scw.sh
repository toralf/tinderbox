# #!/bin/sh
#
# set -x

# this is a (s)imple (c)hroot (w)rapper to go into a (running) tinderbox image
# it will not mount any file systems like /dev, /proc or so

if [[ $# -ne 1 ]]; then
  echo
  echo " an image name is expected !"
  echo
  exit 1
fi

mnt=$1

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

# if $mnt is still invalid than chroot should tell this
#
sudo /usr/bin/chroot $mnt

exit $?
