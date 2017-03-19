# #!/bin/sh
#
# set -x

# this is a (s)imple (c)hroot (w)rapper to go into a (running) tinderbox image
# it will not mound any file systems like /dev, /proc and so on

mnt=$1

# guess a location if just the name is given
#
if [[ ! -d $mnt ]]; then
  mnt=$(ls -d /home/tinderbox/{run,img?}/$mnt 2>/dev/null | head -n 1)
  if [[ ! -d $mnt ]]; then
    echo "cannot guess the full path to the image"
    exit 1
  fi
  echo
  echo " no full path were given, choosing: $mnt"
  echo
fi

sudo /usr/bin/chroot $mnt

exit $?
