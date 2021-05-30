# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

**side note**:
I started with 2-3 dozen lines of one or two shell scripts.
Unfortunately I missed the point of no return when I added additional 2-3 KLOC.
Whilst it works and will be maintained I do not plan to add additional functionality to it.

## usage
### create a new image

```bash
setup_img.sh
```
The current *stage3* file is downloaded, verified and unpacked, profile, keyword and USE flag are set.
Mandatory portage config files will be compiled.
Few required packages will be installed.
A backlog is filled up with all available package in a randomized order (*/var/tmp/tb/backlog*).
A symlink is made into *~/run* and the image is started.

### start an image

```bash
start_img.sh <image>
```
The wrapper *bwrap.sh* handles all sandbox related actions and gives control to *job.sh* which is the heart of the tinderbox.

Without any arguments all symlinks in *~/run* are processed.

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
This uses bubblewrap (a better chroot, see https://github.com/containers/bubblewrap).

### removal of an image

Stop the image and remove the symlink in *~/run*.
The image itself will stay in its data dir till that is cleanud up.

### status of all images

```bash
whatsup.sh -otlpc
```
### report findings

New findings are send via email to the user specified in the variable *mailto*.
Bugs are be filed using *bgo.sh*. A copy+paste ready command line is included in the bug email.

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
Edit the credentials in *~tinderbox/sdata* and strip away the suffix *.sample*, set ownership/rwx-access of this subdirectory and its files to user *root* only.
Grant sudo rights to the user *tinderbox*:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/setup_img.sh,/opt/tb/bin/cgroup.sh
```

Maybe create this crontab entries for user *tinderbox*:

```bash
# crontab of tinderbox
#
@reboot sudo /opt/tb/bin/cgroup.sh; /opt/tb/bin/start_img.sh

* * * * * /opt/tb/bin/logcheck.sh

# replace an image
@hourly l=/tmp/replace_img.sh.log.$$ && /opt/tb/bin/replace_img.sh -s '-j3' &>$l; cat $l; rm $l
```
Watch the mailbox for cron outputs.

## link(s)

https://www.zwiebeltoralf.de/tinderbox.html

