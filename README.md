# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## usage
###setup of a new image
The setup of a new image is made by *tbs.sh* (*at* from *sys-process/at* schedules a command for later, catches the output and email it to the user)
    
    (cd ~/img2; echo "sudo ~/tb/bin/tbs.sh" | at now + 0 min)

A profile, keyword and a USE flag set are choosen.
The current stage3 file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled.
Few required packages (*ssmtp*, *pybugz* etc.) are installed.
The package list */tmp/packages* is created from all visible packages.
The upgrade of GCC and the switch to libressl - if applicable - are scheduled as the first tasks.
A symlink is made into *~/run*.

###start of an image
    
    ~/tb/bin/start_img.sh <image name>

The wrapper *runme.sh* uses *chr.sh* to handle all chroot related actions and calls the tinderbox script *job.sh* itself.
The file */tmp/LOCK* is created to avoid 2 parallel starts.
Without an image name all symlinks in *~/run* are processed.

###stop of an image

    ~/tb/bin/stop_img.sh <image name>

A marker (*/tmp/STOP*) is made in that image.
The current emerge operation will be finished before *job.sh* exits and */tmp/LOCK* is removed.

###removal of an image
Just remove the symlink in *~/run* and the log file in *~/logs*.
The chroot image itself will be kept around until the data dir is overwritten.

###reported findings
All findings are reported email to the user specified in the variable *mailto*.
Bugs can be filed using *bgo.sh*.

###manually bug hunting within an image
1. stop an image
2. chroot into it

    sudo ~/tb/bin/chr.sh <image name>
3. inspect/adapt files in */etc/portage/packages.*
4. do your work
5. exit and start the image

###test a (long runnning) package
Append the package list in the following way:
    
    cat <<<EOF >> <image name>/tmp/packages
    STOP this text is displayed as the subject of an email
    package1
    package2
    %action1
    package3
    ...
    EOF

Use "STOP" instead "INFO" to stop the image afterwards.

## installation
Create the user *tinderbox*

    useradd -m tinderbox
Create few tinderbox and one or more big directories to hold the chroot images, preferred namespace : ~/img*X*, eg. run in its home directory */home/tinderbox*

    mkdir ~/img{1,2} ~/logs ~/run ~/tb
Copy *./bin*, *./data* and *./sdata* into *~/tb*.
Edit the files in *~/sdata* and strip away the suffix *.sample*.
Grant to the user these sudo rights:

    tinderbox ALL=(ALL) NOPASSWD: /home/tinderbox/tb/bin/chr.sh,/home/tinderbox/tb/bin/tbs.sh,/usr/bin/chroot

At a hardened host these tweaks of *Grsecurity* are needed:

    sysctl -w kernel.grsecurity.chroot_deny_chmod=0
    sysctl -w kernel.grsecurity.chroot_caps=0
    sysctl -w kernel.grsecurity.chroot_deny_mount=0
    sysctl -w kernel.grsecurity.tpe=0

## more info
https://www.zwiebeltoralf.de/tinderbox.html

