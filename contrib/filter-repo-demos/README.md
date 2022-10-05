## Background

filter-repo is not merely a history rewriting tool, it also contains a
library that can be used to write new history rewriting tools.  This
directory contains several examples showing the breadth of different things
that could be done.

## Quick overview

Command&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; |Description
-------|-----------
barebones-example    |Simple example with no modifications to filter-repo behavior, just showing what to import and run.
insert-beginning     |Add a new file (e.g. LICENSE/COPYING) to the beginning of history.
signed-off-by        |Add a Signed-off-by tag to a range of commits
lint-history         |Run some lint command on all non-binary files in history.
clean-ignore         |Delete files from history which match current gitignore rules.
filter-lamely (or filter&#8209;branch&#8209;ish) |A nearly bug compatible re-implementation of filter-branch (the git testsuite passes using it instead of filter-branch), with some performance tricks to make it several times faster (though it's still glacially slow compared to filter-repo).
bfg-ish              |A re-implementation of most of BFG Repo Cleaner, with new features and bug fixes.
convert-svnexternals |Insert Git submodules according to SVN externals.

## Purpose

Please note that the point of these examples is not to provide new complete
tools, but simply to demonstrate that extremely varied history rewriting
tools can be created which automatically inherit lots of useful base
functionality: rewriting hashes in commit messages, pruning commits that
become empty, handling filenames with funny characters, non-standard
encodings, handling of replace refs, etc.  (Additional examples of using
filter-repo as a library can also be found in [the
testsuite](../../t/t9391/).)  My sincerest hope is that these examples
provide lots of useful functionality, but that each is missing at least one
critical piece for your usecase.  Go forth and extend and improve.

## Usage

All the examples require a symlink to git-filter-repo in your PYTHONPATH
named git_filter_repo.py in order to run; also, all have a --help flag to
get a description of their usage and flags.
