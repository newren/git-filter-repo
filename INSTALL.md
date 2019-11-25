# What/why/where to install things

filter-repo only consists of a few files that need to be installed:

  * git-filter-repo

    This can be installed in the directory pointed to by `git --exec-path`,
    or placed anywhere in $PATH.  This is the only thing needed for basic use.

    If your python3 executable is named "python" instead of "python3"
    (this particularly appears to affect a number of Windows users),
    then you'll also need to modify the first line of git-filter-repo
    to replace "python3" with "python".

  * git_filter_repo.py

    If you want to make use of one of the scripts in contrib/filter-repo-demos/,
    or want to write your own script making use of filter-repo as a python
    library, then you need to have a symlink to (or copy of) git-filter-repo
    named git_filter_repo.py in $PYTHONPATH.

  * git-filter-repo.1

    If you want `git filter-repo --help` to display the manpage, this needs
    to be copied into $MANDIR/man1/ where $MANDIR is some entry from $MANPATH.

  * git-filter-repo.html

    The manpage is good enough for me and my systems, but an html-formatted
    version of the same page is provided for those who prefer it.  Place it
    where ever you like; I have no idea where such a thing should go.

# Installation via Makefile

Installing should be doable by hand, but a Makefile is provided for those
that prefer it.  However, usage of the Makefile really requires overridding
at least a couple of the directories with sane values, e.g.

    $ make prefix=/usr pythondir=/usr/lib64/python3.8/site-packages install

Also, the Makefile will not edit the shebang line (the first line) of
git-filter-repo if your python executable is not named "python3";
you'll still need to do that yourself.

# Installation via [pip](https://pip.pypa.io/)

Coming soon; see [PR #16](https://github.com/newren/git-filter-repo/pull/16).

# Installation via Package Manager

There are [package
managers](https://alternativeto.net/software/yellowdog-updater-modified/?license=opensource)
for most operating systems; from
[dnf](https://github.com/rpm-software-management/dnf) or
[yum](http://yum.baseurl.org/) or
[apt-get](https://www.debian.org/doc/manuals/debian-reference/ch02.en.html)
or whatever for Linux, to [brew](https://brew.sh/) for Mac OS X, to
[scoop](https://scoop.sh/) for Windows.  Nearly any of these tools
will reduce the installation instructions down to

    $ PACKAGE_TOOL install git-filter-repo

I have no interest in tracking all these pre-built packages (nor
whether those who packaged git-filter-repo have made modifications or
left parts of it out), but apparently https://repology.org is willing
to track who has packaged it.  So, using repology's packaging status
link, the following package managers have packaged git-filter-repo:

[![Packaging status](https://repology.org/badge/vertical-allrepos/git-filter-repo.svg)](https://repology.org/project/git-filter-repo/versions)
