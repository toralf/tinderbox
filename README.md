# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## usage
### create a new image

    cd ~/img; setup_img.sh

The current *stage3* file is downloaded, verified and unpacked, profile, keyword and USE flag are set.
Mandatory portage config files will be compiled.
Few required packages (*ssmtp*, *pybugz* etc.) will be installed.
A backlog is filled up with all available package in a randomized order (*/var/tmp/tb/backlog*).
A symlink is made into *~/run* and the image is started.

### start an image
    
    start_img.sh <image>

The file */var/tmp/tb/LOCK* is created within that image to avoid 2 running instances of the same image.
The wrapper *chr.sh* handles all chroot related actions and gives control to *job.sh*.
That script is the heart of the tinderbox.

Without any arguments all symlinks in *~/run* are processed.

### stop an image

    stop_img.sh <image>

A marker file */var/tmp/tb/STOP* is created in that image.
The current emerge operation will be finished before *job.sh* removes */var/tmp/tb/{LOCK,STOP}* and exits.

### chroot into a stopped image
    
    sudo /opt/tb/bin/chr.sh <image>

This bind-mount all desired directories from the host system. Without any argument an interactive login is made afterwards. Otherwise the argument(s) are treated as command(s) to be run within that image before the chroot is left.

### chroot into a running image
    
    sudo /opt/tb/bin/scw.sh <image>

Simple wrapper of chroot with few checks, no hosts files are mounted. This can be made if an image is already running and therefore *chr.sh* can't be used. This script is useful to inspect log files and to run commands like *eix*, *qlop* etc.

### removal of an image
Stop the image and remove the symlink in *~/run*.
The image itself will stay in one of the data dirs till the next mkfs run.

### status of all images

    whatsup.sh -otlp

### report findings
New findings are send via email to the user specified in the variable *mailto*.
Bugs can be filed using *bgo.sh* - a comand line ready for copy+paste is in the email.

### manually bug hunting within an image
1. stop image if it is running
2. chroot into it
3. inspect/adapt files in */etc/portage/packages.*
4. do your work in */usr/local/portage* to test new/changed ebuilds (do not edit files in */usr/portage*, that rectory is bind-mounted from the host)
5. exit from chroot

### unattended test of package/s
Append package(s) to the package list in the following way:
    
    cat << EOF >> ~/run/[image]/var/tmp/tb/backlog.1st
    INFO net-p2p/bitcoind ok ? https://bugs.gentoo.org/show_bug.cgi?id=642934
    net-p2p/bitcoind
    EOF

*STOP* can be used instead *INFO* to stop the image at that point, the following text will become the subject of an email.

### misc
The script *update_backlog.sh* feeds repository updates into the file *backlog.upd* of each image.
*retest.sh* is used to undo any package specific (mask) changes to portage files before it to schedules an emerge of the package afterwards.
*logcheck.sh* is a helper to notify about non-empty log file(s).
*replace_img.sh* stops an older and spins up a new image based on age and amount of installed packages.

## installation
Create the user *tinderbox*:

    useradd -m tinderbox
    usermod -a -G portage tinderbox

Run as *root*:

    mkdir /opt/tb
    chmod 750 /opt/tb
    chgrp tinderbox /opt/tb

Run as user *tinderbox* in ~ :

    mkdir img{1,2} logs run tb

to have 2 directories acting as mount points for 2 separate file systems (mkfs is *much* more faster than rm -rf) to hold the chroot images. Use both file systems in a round robin manner, start with the first, eg.:

    ln -s img1 img

Clone this git repository.

Move *./data* and *./sdata* into *~/tb/ as user *tinderbox*.
Move *./bin* into */opt/tb/ as user *root*.
The user *tinderbox* must not be allowed to edit the scripts in */opt/tb/bin*.
The user *tinderbox* must have write permissions for files in *~/tb/data*.
Edit the credentials in *~/sdata* and strip away the suffix *.sample*, set this subdirectory to 700 for user *root*.
Grant sudo rights to the user *tinderbox*:

    tinderbox ALL=(ALL) NOPASSWD: /opt/tb/bin/chr.sh,/opt/tb/bin/scw.sh,/opt/tb/bin/setup_img.sh

## (few) more info
https://www.zwiebeltoralf.de/tinderbox.html
