# tinderbox
The goal is to detect build issues of and conflicts between Gentoo packages.

## used scripts
The setup of an image is made by *tbs.sh*. The script *chr.sh* is used to bind-mount host directories onto their chroot mount point counterparts. The wrapper *runme.sh* supports a smooth upgrade of the tinderbox script *job.sh* itself. Bugs are filed with *bgo.sh*. Install artefacts are detected by *PRE-CHECK.sh* script. Latest ebuilds are put on top of arbitrarily choosen package lists by *insert_pkgs.sh*.

## data files
There are files shared to all images: the portage files *package.{accept_keywords,env,mask,unmask,use}.common*, pattern files to *CATCH_ISSUES* and to *IGNORE_ISSUES*, *ALREADY_CATCHED* helps to avoid filing more than one bug for the same package *IGNORE_PACKAGES* prevents its entries from being emerged explicitely.

## installation
Copy *bin* and *data* into */home/tinderbox/tb*, create a directory to hold the chroot images (i.e. *images2*) and start your own tinderbox.

## typical calls
Setup a new image:

    $> echo "sudo ~/tb/bin/tbs.sh -A -m unstable -i ~/images2 -p default/linux/amd64/13.0/desktop/kde" | at now

Start all not-running images:

    $> ~/tb/bin/start_img.sh


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox too.

