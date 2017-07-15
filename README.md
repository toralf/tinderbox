# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## usage
### create a new image
The setup of a new image is made by *tbs.sh* (*at* from *sys-process/at* schedules a command for later, catches the output and email it to the user)
    
    echo "cd ~/img2; sudo /opt/tb/bin/tbs.sh" | at now + 0 min

A profile, keyword and a USE flag set are choosen.
The current stage3 file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled.
Few required packages (*ssmtp*, *pybugz* etc.) are installed.
The package list */tmp/packages* is created from all visible packages.
The upgrade of GCC and the switch to libressl - if applicable - are scheduled as the first tasks.
A symlink is made into *~/run* and the image is started.

### start an image
    
    start_img.sh <image>

The wrapper *chr.sh* handles all chroot related actions and calls the tinderbox script *job.sh* itself.
The file */tmp/LOCK* is created to avoid 2 parallel starts.
Without an argument all symlinks in *~/run* are processed.

### stop an image

    stop_img.sh <image>

A marker (*/tmp/STOP*) is made in that image.
The current task operation will be finished before *job.sh* removes */tmp/LOCK* and exits.

### chroot into a stopped image
    
    sudo /opt/tb/bin/chr.sh <image with dir>

This bind-mounts all host-related dirs. Without any argument then an interactive login is made. Otherwise the arguments are treated as command(s) to be run within that image and an exit is made afterwards.

### chroot into a running image
    
    sudo /opt/tb/bin/scw.sh <image>

Simple wrapper of chroot with few checks.

### removal of an image
Just remove the symlink in *~/run*.
The chroot image itself will be kept around in the data dir.

### status of all images

    whatsup.sh -otlp

### report findings
New findings are send via email to the user specified in the variable *mailto*.
Bugs can be filed using *bgo.sh* - a comand line ready for copy+paste is in the email.

### manually bug hunting within an image
1. stop image if it is running
2. chroot into it
3. inspect/adapt files in */etc/portage/packages.*
4. do your work in */usr/local/portage* to test new/changed ebuilds (do not edit files in */usr/portage*, that is sbind-mountedi from the host)
5. exit from chroot

### unattended test of package/s
Append package/s to the package list in the following way:
    
    cat <<<EOF >> ~/run/[image]/tmp/packages
    INFO this text is the subject of an info email (body is empty)
    package1
    ...
    %action1
    ...
    packageN
    ...
    EOF

"STOP" can be used instead "INFO" to stop the image at that point.

### misc
The script *insert_pkgs.sh* adds periodically new or change ebuilds on top of arbitrary package lists. *retest_pkgs.sh* is used to revert image specific changes made by *job.sh* to portage files related to the given package(s). And finally *logcheck.sh* is a helper to notify about log file contenst (which should be empty mostly).


## installation
Create the user *tinderbox*:

    useradd -m tinderbox
Run in */home/tinderbox*:

    mkdir ~/img{1,2} ~/logs ~/run ~/tb
Copy *./data* and *./sdata* into *~/tb* and *./bin* into */opt/tb*.
The user tinderbox must not be allowed to edit the scripts in */opt/tb/bin*.
The user must have write permissions for the files in *~/tb/data*.
Edit files in *~/sdata* and strip away the suffix *.sample*.
Grant sudo rights:

    tinderbox ALL=(ALL) NOPASSWD: /opt/tb/bin/chr.sh,/opt/tb/bin/scw.sh,/opt/tb/bin/tbs.sh

At a hardened Gentoo tweak *GRsecurity* if appropriate:

    sysctl -w kernel.grsecurity.chroot_deny_chmod=0
    sysctl -w kernel.grsecurity.chroot_caps=0
    sysctl -w kernel.grsecurity.chroot_deny_mount=0
    sysctl -w kernel.grsecurity.tpe=0

## more info
https://www.zwiebeltoralf.de/tinderbox.html

