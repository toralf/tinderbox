[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# tinderbox

The goal is to detect build issues of and conflicts between Gentoo Linux packages.

For that a dozen or more Gentoo images are running in parallel using a sandbox ([bubblewrap](https://github.com/containers/bubblewrap) or as non-default the good old _chroot_).

Each image is setup from a recent _stage3_ tarball as an arbitrary combination of _~amd64_ + _profile_ + _USE flag_ set.
Within each image all Gentoo packages are scheduled in a randomized order for emerge.

## usage

### create a new image

```bash
setup_img.sh
```

The current _stage3_ file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled and few required packages will be installed.
A backlog is filled up with all recent packages in a randomized order.
A symlink is made into _~tinderbox/run_ and the image is started.

### start an image

```bash
start_img.sh <image>
```

Without any arguments all symlinks in _~tinderbox/run_ are started.

The wrapper _bwrap.sh_ handles all sandbox related actions and starts _job.sh_ within that image.

### stop an image

```bash
stop_img.sh <image>
```

A marker file _/var/tmp/tb/STOP_ is created in that image.
The current emerge operation will be finished before _job.sh_ removes the marker file and exits.

### go into a stopped image

```bash
sudo /opt/tb/bin/bwrap.sh -m <image>
```

### removal of an image

Stop the image and remove the symlink in _~tinderbox/run_.
The image itself will stay in its data dir till that is cleaned up.

### status of all images

```bash
whatsup.sh -decp
watch whatsup.sh -otl
```

### report findings

The file _~tinderbox/tb/data/ALREADY_CAUGHT_ holds reported findings.
A new finding is send via email to the user specified by the variable _MAILTO_.
The Gentoo bugzilla can be searched by _check_bgo.sh_ for dups/similarities.
A finding can be filed using _bgo.sh_.

## installation

Create the user _tinderbox_:

```bash
useradd -m tinderbox
usermod -a -G portage tinderbox
```

Run as _root_:

```bash
mkdir /opt/tb
chmod 750 /opt/tb
chgrp tinderbox /opt/tb
```

Run as user _tinderbox_ in _~tinderbox_ :

```bash
mkdir distfiles img logs run tb
```

Clone this Git repository.

Move _./data_ and _./sdata_ into _~tinderbox/tb/_.
Move _./bin_ under _/opt/tb/_ as user _root_.
The user _tinderbox_ must not be allowed to edit the scripts in _/opt/tb/bin_.
The user _tinderbox_ must have write permissions for files in _~tinderbox/tb/data_.
Edit the ssmtp credentials in _~tinderbox/sdata_ and strip away the suffix _.sample_, set ownership and grant permissions of this subdirectory and its files to user _root_ only.
Grant the user _tinderbox_ these sudo rights:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/setup_img.sh,/opt/tb/bin/house_keeping.sh
```

Create crontab entries for user _tinderbox_:

```bash
# crontab of tinderbox
#

# start web service
@reboot   cd ~/img && nice /opt/fuzz-utils/simple-http-server.py --address x.y.z --port 12345 &>/tmp/web-tinderbox.log

# start images
@reboot   rm -f ~tinderbox/run/*/var/tmp/tb/STOP; /opt/tb/bin/start_img.sh

# check logs
@reboot   while :; do sleep 60; /opt/tb/bin/logcheck.sh; done

# run 13 images in parallel
@hourly   f=$(mktemp /tmp/XXXXXX); /opt/tb/bin/replace_img.sh -n 13 &>$f; cat $f; rm $f

# house keeping
@daily    sudo /opt/tb/bin/house_keeping.sh
```

and this as _root_ (because the _local_ cgroup is used by other users too):

```bash
@reboot   /opt/tb/bin/cgroup.sh
```

## link(s)

https://www.zwiebeltoralf.de/tinderbox.html
