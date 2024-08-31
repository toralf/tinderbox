[![StandWithUkraine](https://raw.githubusercontent.com/vshymanskyy/StandWithUkraine/main/badges/StandWithUkraine.svg)](https://github.com/vshymanskyy/StandWithUkraine/blob/main/docs/README.md)

# tinderbox

## Goal

The goal is to detect build issues/conflicts of Gentoo Linux packages.
For that about a dozen sandbox'ed Gentoo images are running in parallel.
Each image is setup from a recent _stage3_ tarball as an arbitrary combination of _~amd64_ + _profile_ + _USE flag_ set.
Within each image all Gentoo packages are in a randomized order scheduled to be installed.

## Usage

Setup of images is done by _setup_img.sh_.
Then watch the status:

```bash
whatsup.sh -dcp
whatsup.sh -otl
```

The file _~tinderbox/tb/findings/ALREADY_CAUGHT_ holds reported findings.
A new finding is send via email to the user specified by the variable _MAILTO_.
The Gentoo bug tracker can be searched for related bugs using _check_bgo.sh_.
If not reported a finding can be filed using _bgo.sh_.

## Installation

Create the user _tinderbox_, which :

1. must not be allowed to edit files under _/opt/tb/_
1. needs to be granted to read/execute the scripts under _/opt/tb/bin/_
1. must have read/write permissions for files under _~tinderbox/tb/_
1. must not be allowed to read the file under _/opt/tb/sdata/_.

Create in its HOME the directories: _./distfiles/_, _./img/_, _./logs/_, _./run/_ and _./tb/_.
Clone this Git repository or unpack a release artefact.
Move _./conf_, _./data_ and _./patches_ to _~tinderbox/tb/_.
Move _./bin_ and _./sdata_ to _/opt/tb/_ and set ownership to _root_.

Edit the credentials in _ssmtp.conf.sample_ and strip away the suffix _.sample_ from the file.
Grant to the user _tinderbox_ these sudo rights:

```bash
tinderbox  ALL=(ALL) NOPASSWD: /opt/tb/bin/bwrap.sh,/opt/tb/bin/setup_img.sh,/opt/tb/bin/house_keeping.sh,/opt/tb/bin/kill_img.sh,/opt/tb/bin/retest.sh,/opt/tb/bin/collect_data.sh,/usr/sbin/emaint
```

## Disclaimer

I missed the point of no return to switch from bash script to Python when I started this project.

## Links

[homepage](https://www.zwiebeltoralf.de/tinderbox.html)
