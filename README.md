# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## scripts
The setup of an image is made by *tbs.sh*. An image is started with *start_img.sh* and stopped with *stop_img.sh*. Bugs are filed with *bgo.sh*. Install artefacts are detected by *PRE-CHECK.sh* script. Latest ebuilds are put on top of each package list by *insert_pkgs.sh*.
The helper script *chr.sh* is used to bind-mount host directories onto their chroot mount point counterparts. The wrapper *runme.sh* supports a smooth upgrade of the tinderbox script *job.sh* itself.

## installation
Copy both *bin* and *data* into */home/tinderbox/tb*, point a (big) directory to */home/tinderbox/images* and start your first own tinderbox. Don't forget to grant sudo rights to the user for *chr.sh* and *tbs.sh*.

## typical calls
Setup a new image:

    $> sudo ~/tb/bin/tbs.sh 

Start it:

    $> ~/tb/bin/start_img.sh


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

