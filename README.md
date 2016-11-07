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

It basically parse the output of *cat /tmp/packages | xargs -n1 emerge -u*.
Its wrapper *runme.sh* supports the development while copies of it are running.
It uses *chr.sh* to handle chroot related actions.

New issues are reported via email to the user. Bugs can then be filed using *bgo.sh*.

## installation
Copy both *bin* and *data* into */home/tinderbox/tb*.
Point a (big) directory to */home/tinderbox/images*. Create an sdata subdir there too containing the files *ssmtp.conf* and *.bugzrc*. Grant sudo rights to the user *tinderbox* for *chr.sh* and *tbs.sh*.

## typical calls
Setup a new image:

    $> sudo ~/tb/bin/tbs.sh 

Start it:

    $> ~/tb/bin/start_img.sh


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

