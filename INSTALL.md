# Table of Contents

  * [Pre-requisites](#pre-requisites)
  * [Simple Installation](#simple-installation)
  * [Installation via Package Manager](#installation-via-package-manager)
  * [Detailed installation explanation for
     packagers](#detailed-installation-explanation-for-packagers)
  * [Installation as Python Package from
     PyPI](#installation-as-python-package-from-pypi)
  * [Installation via Makefile](#installation-via-makefile)
  * [Notes for Windows Users](#notes-for-windows-users)

# Pre-requisites

Instructions on this page assume you have already installed both
[Git](https://git-scm.com) and [Python](https://www.python.org/)
(though the [Notes for Windows Users](#notes-for-windows-users) has
some tips on Python).

# Simple Installation

All you need to do is download one file: the [git-filter-repo script
in this repository](git-filter-repo) ([direct link to raw
file](https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo)),
making sure to preserve its name (`git-filter-repo`, with no
extension).  **That's it**.  You're done.

Then you can run any command you want, such as

    $ python3 git-filter-repo --analyze

If you place the git-filter-repo script in your $PATH, then you can
shorten commands by replacing `python3 git-filter-repo` with `git
filter-repo`; the manual assumes this but you can use the longer form.

Optionally, if you also want to use some of the contrib scripts, then
you need to make sure you have a `git_filter_repo.py` file which is
either a link to or copy of `git-filter-repo`, and you need to place
that git_filter_repo.py file in $PYTHONPATH.

If you prefer an "official" installation over the manual installation
explained above, the other sections may have useful tips.

# Installation via Package Manager

If you want to install via some [package
manager](https://alternativeto.net/software/yellowdog-updater-modified/?license=opensource),
you can run

    $ PACKAGE_TOOL install git-filter-repo

The following package managers have packaged git-filter-repo:

[![Packaging status](https://repology.org/badge/vertical-allrepos/git-filter-repo.svg)](https://repology.org/project/git-filter-repo/versions)

This list covers at least Windows (Scoop), Mac OS X (Homebrew), and
Linux (most the rest).  Note that I do not curate this list (and have
no interest in doing so); https://repology.org tracks who packages
these versions.

# Detailed installation explanation for packagers

filter-repo only consists of a few files that need to be installed:

  * git-filter-repo

    This is the _only_ thing needed for basic use.

    This can be installed in the directory pointed to by `git --exec-path`,
    or placed anywhere in $PATH.

    If your python3 executable is named "python" instead of "python3"
    (this particularly appears to affect a number of Windows users),
    then you'll also need to modify the first line of git-filter-repo
    to replace "python3" with "python".

  * git_filter_repo.py

    This is needed if you want to make use of one of the scripts in
    contrib/filter-repo-demos/, or want to write your own script making use
    of filter-repo as a python library.

    You can create this symlink to (or copy of) git-filter-repo named
    git_filter_repo.py and place it in your python site packages; `python
    -c "import site; print(site.getsitepackages())"` may help you find the
    appropriate location for your system.  Alternatively, you can place
    this file anywhere within $PYTHONPATH.

  * git-filter-repo.1

    This is needed if you want `git filter-repo --help` to succeed in
    displaying the manpage, when help.format is "man" (the default on Linux
    and Mac).

    This can be installed in the directory pointed to by `$(git
    --man-path)/man1/`, or placed anywhere in $MANDIR/man1/ where $MANDIR
    is some entry from $MANPATH.

    Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the manpage is installed.

  * git-filter-repo.html

    This is needed if you want `git filter-repo --help` to succeed in
    displaying the html version of the help, when help.format is set to
    "html" (the default on Windows).

    This can be installed in the directory pointed to by `git --html-path`.

    Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the html version of help is
    installed.

So, installation might look something like the following:

1. If you don't have the necessary documentation files (because you
   are installing from a clone of filter-repo instead of from a
   tarball) then you can first run:

   `make snag_docs`

   (which just copies the generated documentation files from the
   `docs` branch)

2. Run the following

   ```
   cp -a git-filter-repo $(git --exec-path)
   cp -a git-filter-repo.1 $(git --man-path)/man1 && mandb
   cp -a git-filter-repo.html $(git --html-path)
   ln -s $(git --exec-path)/git-filter-repo \
       $(python -c "import site; print(site.getsitepackages()[-1])")/git_filter_repo.py
   ```

or you can use the provided Makefile, as noted below.

# Installation as Python Package from PyPI

`git-filter-repo` is also available as 
[PyPI-package](https://pypi.org/project/git-filter-repo/). 

Therefore, it can be installed with [pipx](https://pypa.github.io/pipx/) 
or [uv tool](https://docs.astral.sh/uv/concepts/tools/). 
Command example for pipx:

`pipx install git-filter-repo`

# Installation via Makefile

Installing should be doable by hand, but a Makefile is provided for those
that prefer it.  However, usage of the Makefile really requires overridding
at least a couple of the directories with sane values, e.g.

    $ make prefix=/usr pythondir=/usr/lib64/python3.8/site-packages install

Also, the Makefile will not edit the shebang line (the first line) of
git-filter-repo if your python executable is not named "python3";
you'll still need to do that yourself.

# Notes for Windows Users

git-filter-repo can be installed with multiple tools, such as 
[pipx](https://pypa.github.io/pipx/) or a Windows-specific package manager
like Scoop (both of which were covered above).

Sadly, Windows sometimes makes things difficult.  Common and historical issues:

  * **Non-functional Python stub**: Windows apparently ships with a
    [non-functional
    python](https://github.com/newren/git-filter-repo/issues/36#issuecomment-568933825).
    This can even manifest as [the app
    hanging](https://github.com/newren/git-filter-repo/issues/36) or
    [the system appearing to
    hang](https://github.com/newren/git-filter-repo/issues/312).  Try
    installing
    [Python](https://docs.microsoft.com/en-us/windows/python/beginners)
    from the [Microsoft
    Store](https://apps.microsoft.com/store/search?publisher=Python%20Software%20Foundation)
  * **Modifying PATH, making the script executable**: If modifying your PATH
    and/or making scripts executable is difficult for you, you can skip that
    step by just using `python3 git-filter-repo` instead of `git filter-repo`
    in your commands.
  * **Different python executable name**:  Some users don't have
    a `python3` executable but one named something else like `python`
    or `python3.8` or whatever.  You may need to edit the first line
    of the git-filter-repo script to specify the appropriate path.  Or
    just don't bother and instead use the long form for executing
    filter-repo commands.  Namely, replace the `git filter-repo` part
    of commands with `PYTHON_EXECUTABLE git-filter-repo`. (Where
    `PYTHON_EXECUTABLE` is something like `python` or `python3.8` or
    `C:\PATH\TO\INSTALLATION\OF\python3.exe` or whatever).
  * **Symlink issues**:  git_filter_repo.py is supposed to be a symlink to
    git-filter-repo, so that it appears to have identical contents.
    If your system messed up the symlink (usually meaning it looks like a
    regular file with just one line), then delete git_filter_repo.py and
    replace it with a copy of git-filter-repo.
  * **Old GitBash limitations**: older versions of GitForWindows had an
    unfortunate shebang length limitation (see [git-for-windows issue
    #3165](https://github.com/git-for-windows/git/pull/3165)).  If
    you're affected, just use the long form for invoking filter-repo
    commands, i.e. replace the `git filter-repo` part of commands with
    `python3 git-filter-repo`.

For additional historical context, see:
  * [#371](https://github.com/newren/git-filter-repo/issues/371#issuecomment-1267116186)
  * [#360](https://github.com/newren/git-filter-repo/issues/360#issuecomment-1276813596)
  * [#312](https://github.com/newren/git-filter-repo/issues/312)
  * [#307](https://github.com/newren/git-filter-repo/issues/307)
  * [#225](https://github.com/newren/git-filter-repo/pull/225)
  * [#231](https://github.com/newren/git-filter-repo/pull/231)
  * [#124](https://github.com/newren/git-filter-repo/issues/124)
  * [#36](https://github.com/newren/git-filter-repo/issues/36)
  * [this git mailing list
     thread](https://lore.kernel.org/git/nycvar.QRO.7.76.6.2004251610300.18039@tvgsbejvaqbjf.bet/)
