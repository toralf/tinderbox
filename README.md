# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## scripts
The setup of a new image is made by *tbs.sh*.

A profile, keyword and a USE flag set are choosen.
The the latest stage3 is downloaded, verified and unpacked.
The package list is filled with all known packages.
Portage config files are compiled.
Few mandatory packages (MTA, bugz etc.) are installed.

The tinderbox script itself is *job.sh*.

It runs over the package list till an image is stopped or its package list is empty.
The wrapper *runme.sh* supports developing of the script *job.sh* w/o interrupting running images.
It uses *chr.sh* is used to chroot into an image. 

New issues are reported via email to the user. Bugs can then be filed using *bgo.sh*.

## installation
Copy both *bin* and *data* into */home/tinderbox/tb*.
Point a (big) directory to */home/tinderbox/images*.
Grant sudo rights to the user *tinderbox* for *chr.sh* and *tbs.sh*.

## typical calls
Setup a new image:

    $> sudo ~/tb/bin/tbs.sh 

Start it:

    $> ~/tb/bin/start_img.sh


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

