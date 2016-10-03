# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## scripts
The setup of an image is made by *tbs.sh*.

A profile, keyword and the USE flag sets are choosen, portage config files are compiled and few mandatory packages (MTA, bugz etc.) are installed. Eventually the package list is filled with all known packages.

The tinderbox script itself is *job.sh*.

It runs over the package list till the image is stopped or the package list is empty. The wrapper *runme.sh* supports a smooth upgrade of it.

An image is started with *start_img.sh* and stopped with *stop_img.sh*. The *chr.sh* is used to chroot into it, before it bind-mount host directories onto their chroot mount point counterparts. Install artefacts are detected by *PRE-CHECK.sh* script. Latest ebuilds are put on top of each package list by *insert_pkgs.sh*. Bugs are filed with *bgo.sh*.

## installation
Copy both *bin* and *data* into */home/tinderbox/tb*, point a (big) directory to */home/tinderbox/images* and start your first own tinderbox. Don't forget to grant sudo rights to the user *tinderbox* for *chr.sh* and *tbs.sh*.

## typical calls
Setup a new image:

    $> sudo ~/tb/bin/tbs.sh 

Start it:

    $> ~/tb/bin/start_img.sh


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

