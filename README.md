# tinderbox
The goal is to detect build issues of and conflicts between Gentoo packages.


## shell scripts
The setup of an image is made by *tbs.sh*.
The helper script *chr.sh* is used to mount host directories and files onto the chroot mount points.
The wrapper *runme.sh* calls the tinderbox script *job.sh*, so a smooth upgrade of the tinderbox script itself can be made.
Bugs are filed with *bgo.sh*.
Install artefacts are detected by *PRE-CHECK.sh* script.
New or updated ebuilds are detected by *insert_pkgs.sh*.


## data files
There are common portage files shared among all images: */etc/portage/package.{accept_keywords,env,mask,unmask,use}.common*,
pattern files to help to *CATCH_ISSUES* and to *IGNORE_ISSUES*,
the file *ALREADY_CATCHED* helps to avoid filing a bug more than once
and a pattern file to *IGNORE_PACKAGES* packages from being emerged explicitely.


## installation
Copy both the *bin* and the *data* directory into the directory: */home/tinderbox/tb*
and create a directory to hold the chroot images (*images2* in the example below).


## typical calls
Setup a new image:

    $> echo "sudo ~/tb/bin/tbs.sh -A -m unstable -i ~/images2 -p default/linux/amd64/13.0/desktop/kde" | at now

Start all not-running images:

    $> ~/tb/bin/start_img.sh


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox too.
