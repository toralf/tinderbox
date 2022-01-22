# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

For that a dozen or more Gentoo images are running in parallel using a sandbox ([bubblewrap](https://github.com/containers/bubblewrap) or as non-default the good old *chroot*).

Each image is setup from a recent *stage3* tarball as an arbitrary combination of *~amd64* + *profile* + *USE flag* set.
Within each image all Gentoo packages are scheduled in a randomized order for emerge.

## usage
### create a new image

```bash
setup_img.sh
```
The current *stage3* file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled and few required packages will be installed.
A backlog is filled up with all recent packages in a randomized order.
A symlink is made into *~tinderbox/run* and the image is started.

### start an image
```bash
start_img.sh <image>
```
Without any arguments all symlinks in *~tinderbox/run* are started.

The wrapper *bwrap.sh* handles all sandbox related actions and starts *job.sh* within that image.

### stop an image

```bash
stop_img.sh <image>
```

A marker file */var/tmp/tb/STOP* is created in that image.
The current emerge operation will be finished before *job.sh* removes the marker file and exits.

### go into a stopped image
```bash
sudo /opt/tb/bin/bwrap.sh -m <image>
```

### removal of an image
Stop the image and remove the symlink in *~tinderbox/run*.
The image itself will stay in its data dir till that is cleaned up.

### status of all images
```bash
whatsup.sh -decp
watch whatsup.sh -otl
```

### report findings
The file *~tinderbox/tb/data/ALREADY_FILED* holds reported findings.
A new finding is send via email to the user specified by the variable *MAILTO*.
The Gentoo bugzilla can be searched by *check_bgo.sh* for dups/similarities.
A finding can be filed using *bgo.sh*.

## installation
Create the user *tinderbox*:

```bash
useradd -m tinderbox
usermod -a -G portage tinderbox
```

Run as *root*:

```bash
mkdir /opt/tb
chmod 750 /opt/tb
chgrp tinderbox /opt/tb
```
Run as user *tinderbox* in ~tinderbox :

```bash
mkdir distfiles img logs run tb
```
Clone this Git repository.

Move *./data* and *./sdata* into *~tinderbox/tb/*.
Move *./bin* under */opt/tb/* as user *root*.
The user *tinderbox* must not be allowed to edit the scripts in */opt/tb/bin*.
The user *tinderbox* must have write permissions for files in *~tinderbox/tb/data*.
Edit the ssmtp credentials in *~tinderbox/sdata* and strip away the suffix *.sample*, set ownership and rwx access of this subdirectory and its files to user *root* only.
Grant the user *tinderbox* these these sudo rights:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/setup_img.sh,/opt/tb/bin/house_keeping.sh
```

Create crontab entries for user *tinderbox*:

```bash
# crontab of tinderbox
#

# start images
@reboot   rm -f ~tinderbox/run/*/var/tmp/tb/STOP; /opt/tb/bin/start_img.sh

# check logs
@reboot   while :; do sleep 60; /opt/tb/bin/logcheck.sh; done

# run 13 images in parallel
@hourly   f=$(mktemp /tmp/XXXXXX); /opt/tb/bin/replace_img.sh -n 13 &>$f; cat $f; rm $f

# house keeping
@daily    sudo /opt/tb/bin/house_keeping.sh
```

and this as *root*:

```bash
@reboot   /opt/tb/bin/cgroup.sh
```

## link(s)

https://www.zwiebeltoralf.de/tinderbox.html

