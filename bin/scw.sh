# #!/bin/sh
#
# set -x

# this is a (s)imple (c)hroot (w)rapper for the tinderbox user

dir=$(readlink -f $1 2>&1)
if [[ $? -ne 0 ]]; then
  echo "failure in readlink ?!"
  exit 1
fi

if [[ ! -d $dir ]]; then
  echo "dir '$dir' doesn't exist !"
  exit 2
fi

if [[ ! "$(echo $dir | cut -f1-3 -d'/')" = "/home/tinderbox" ]]; then
  echo "please stay inside of your home !"
  exit 3
fi

sudo /usr/bin/chroot $dir

exit $?
