# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## scripts
###setup
The setup of a new image is made by *tbs.sh*.
A profile, keyword and a USE flag set are choosen.
The current stage3 file is downloaded, verified and unpacked.
The package list is filled with all known packages.
Portage config files are compiled.
Few mandatory packages (*ssmtp*, *pybugz* etc.) are installed.
The switch to libressl - if applicable - and upgrade of GCC are scheduled as the first tasks when the image is started.

###start
The start of a tinderbox image is made by *job.sh*.
It basically parses the output of

    cat /tmp/packages | xargs -n1 emerge -u

It uses *chr.sh* to handle all chroot related actions.

###issues
Issues are reported with all necessary data via email to the user.
Bugs can be filed using *bgo.sh*.

## installation
Copy *bin*, *data* and *sdata* into */home/tinderbox/tb*.
Adapt the 2 files in *sdata* and strip away the suffix *.sample*.
Grant sudo rights to the user *tinderbox* to execute *chr.sh* and *tbs.sh*:
    tinderbox ALL=(ALL) NOPASSWD: /home/tinderbox/tb/bin/chr.sh,/home/tinderbox/tb/bin/tbs.sh,/usr/bin/chroot


## typical calls
Setup a new image:
    sudo ~/tb/bin/tbs.sh 

Start it:
    ~/tb/bin/start_img.sh <image name>


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

