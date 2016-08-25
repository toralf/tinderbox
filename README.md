# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## scripts
The setup of an image is made by *tbs.sh*. An image is started with *start_img.sh* and stopped with *stop_img.sh*. Bugs are filed with *bgo.sh*. Install artefacts are detected by *PRE-CHECK.sh* script. Latest ebuilds are put on top of each package list by *insert_pkgs.sh*.
The helper script *chr.sh* is used to bind-mount host directories onto their chroot mount point counterparts. The wrapper *runme.sh* supports a smooth upgrade of the tinderbox script *job.sh* itself.

## installation
Copy both *bin* and *data* into */home/tinderbox/tb*, create a (big) directory to hold the chroot images, maybe adapt the shell variable *$tbhome* and start your own tinderbox. Grant the user to run *chr.sh* and *tbs.sh*.

## typical calls
Setup a new image:

    $> ./tbs.sh -p default/linux/amd64/13.0/desktop/plasma

Start it:

    $> ./start_img.sh [ <name> ]


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

