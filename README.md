# tinderbox
Gentoo Linux build bot


shell scripts
-------------
The setup of an image is made by tbs.sh.
The helper script chr.sh is used to mount host directories and files onto the chroot mount points.
The wrapper runme.sh calls the tinderbox script job.sh, so a smooth upgrade of the tinderbox script itself can be made.
Bugs are filed with bgo.sh.
Install artefacts are detected by PRE-CHECK.sh script.
New or updated ebuilds are detected by insert_pkgs.sh.


data files
----------
There are common files shared among all images: /etc/portage/package.{accept_keywords,env,mask,unmaskuse}.common,
pattern files to help to CATCH_ISSUES and to IGNORE_ISSUES,
ALREADY_CATCHED helps to avoid filing a bug more than once
and a pattern file to IGNORE_PACKAGES packages from being emerged explicitely.


more info
---------
Have a look at https://www.zwiebeltoralf.de/tinderbox/index.html too.
