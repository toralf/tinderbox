# tinderbox
The goal is to detect build issues of and conflicts between Gentoo Linux packages.

## scripts
The setup of a new image is made by *tbs.sh*.
A profile, keyword and a USE flag set are choosen.
The the latest stage3 is downloaded, verified and unpacked.
The package list is filled with all known packages.
Portage config files are compiled.
Few mandatory packages (MTA, bugz etc.) are installed.
The switch to libressl - if applicable - and upgrade of GCC are scheduled as the first tasks when the image is started.

The start of a tinderbox image is made by *job.sh*.
It basically parses the output of *cat /tmp/packages | xargs -n1 emerge -u*.
It uses *chr.sh* to handle all chroot related actions.

Issues are reported with all necessary data via email to the user.
Bugs can be filed using *bgo.sh*.

## installation
Copy *bin*, *data* and *sdata* into */home/tinderbox/tb*.
Adapt the 2 files in *sdata* and strip away the suffix *.sample*.
Grant sudo rights to the user *tinderbox* to execute *chr.sh* and *tbs.sh*.

## typical calls
Setup a new image:

    $> sudo ~/tb/bin/tbs.sh 

Start it:

    $> ~/tb/bin/start_img.sh <image name>


## more info
Have a look at https://www.zwiebeltoralf.de/tinderbox.html too.

