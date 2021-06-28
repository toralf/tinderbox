# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

For that N Gentoo images are running in parallel using [bubblewrap](https://github.com/containers/bubblewrap) (a better chroot).

Each image is setup from a recent stage3 tarball as an arbitrary combination of *~amd64* + *profile* + *USE flag* + ... set. Within each image all Gentoo packages are scheduled to be emerged in a randomized order.

## usage
### create a new image

```bash
setup_img.sh
```
The current *stage3* file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled and few required packages will be installed.
A backlog is filled up with all rec ent packages in a randomized order.
A symlink is made into *~/run* and the image is started.

### start an image

```bash
start_img.sh <image>
```
Without any arguments all symlinks in *~/run* are processed.

The wrapper *bwrap.sh* handles all sandbox related actions and starts *job.sh* within that image.

### stop an image

```bash
stop_img.sh <image>
```

A marker file */var/tmp/tb/STOP* is created in that image.
The current emerge operation will be finished before *job.sh* removes the marker file and exits.

### go into a stopped image

```bash
sudo /opt/tb/bin/bwrap.sh -m <mount point>
```

This uses

### removal of an image

Stop the image and remove the symlink in *~/run*.
The image itself will stay in its data dir till that is cleanud up.

### status of all images

```bash
whatsup.sh -crpe
watch whatsup.sh -otl
```

### report findings

The file *tb/data/ALREADY_FILED* holds reported findings.
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
Move *./bin* into */opt/tb/ as user *root*.
The user *tinderbox* must not be allowed to edit the scripts in */opt/tb/bin*.
The user *tinderbox* must have write permissions for files in *~tinderbox/tb/data*.
Edit the ssmtp credentials in *~tinderbox/sdata* and strip away the suffix *.sample*, set ownership/rwx-access of this subdirectory and its files to user *root* only.
Grant sudo rights to the user *tinderbox*:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/setup_img.sh,/opt/tb/bin/house_keeping.sh
```

Create these crontab entries for user *tinderbox*:

```bash
# crontab of tinderbox
#
@reboot   rm ~/run/*/var/tmp/tb/STOP; /opt/tb/bin/start_img.sh
* * * * * /opt/tb/bin/logcheck.sh

# replace an image
@hourly   /opt/tb/bin/replace_img.sh

# house keeping
@daily    /opt/tb/bin/house_keeping.sh
```

and this as *root*:

```bash
@reboot   /opt/tb/bin/cgroup.sh
```

Watch the mailbox for cron outputs.

## link(s)

https://www.zwiebeltoralf.de/tinderbox.html

