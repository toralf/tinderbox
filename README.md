# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## installation
Create user *tinderbox* with the home directory */home/tinderbox*.

    useradd -m tinderbox
    mkdir ~/images ~/logs ~/run ~/tb
Unpack *./bin*, *./data* and *./sdata* into *~/tb*.
Edit the files in *sdata* and strip away the suffix *.sample*.
Grant to the user these sudo rights:
    
    tinderbox ALL=(ALL) NOPASSWD: /home/tinderbox/tb/bin/chr.sh,/home/tinderbox/tb/bin/tbs.sh,/usr/bin/chroot

## usage
###setup of a new image
The setup of a new image is made by *tbs.sh*.
    
    cd ~/images; sudo ~/tb/bin/tbs.sh 
A profile, keyword and a USE flag set are choosen and the current stage3 file is downloaded, verified and unpacked.
Mandatory portage config files will be compiled and few mandatory packages (*ssmtp*, *pybugz* etc.) are installed.
The package list */tmp/packages* is created from all visible packages.
The upgrade of GCC and the switch to libressl - if applicable - are scheduled as the first tasks.

###start of an image
The start of a tinderbox image after it was setup is made by *job.sh*.
It uses *chr.sh* to handle the chroot related actions and basically parses the output of *cat /tmp/packages | xargs -n 1 emerge -u*.

###stop of an image
The stop of a tinderbox image is made using
    
    ~/tb/bin/stop_img.sh <image name>

A marker (*/tmp/STOP*) is made within that image.
The current emerge operation has to be finished and *job.sh* will exit.
After this the symlink from *~/run* has to been removed.

###reported findings
All findings are reported with necessary data via email to the user specified in teh variable *mailto*.
Bugs can be filed using *bgo.sh*.

## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

