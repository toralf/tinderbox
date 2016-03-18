# tinderbox
detect build issues of and conflicts between Gentoo packages

./bin           task
==============  ===========================================================
tbs.sh          setup of a new chroot image
chr.sh          mount host dirs and files onto the chroot mount points
runme.sh        wrapper to call job.sh
job.sh          the tinderbox script itself
bgo.sh          wrapper to report bugs to bugzilla
PRE-CHECK.sh    detect install artefacts
insert_pkgs.sh  prepend new or updated ebuilds to the package list

./data
===========================================================================
contains data files shared amoung all images:
  /etc/portage/package.{accept_keywords,env,mask,unmask,use}.common
  pattern files to help to CATCH_ISSUES and to IGNORE_ISSUES,
  ALREADY_CATCHED helps to avoid filing a bug more than once
  pattern file to IGNORE_PACKAGES packages from being emerged explicitely

Have a look at https://www.zwiebeltoralf.de/tinderbox/index.html too.
