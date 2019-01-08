#!/usr/bin/env python

import imp
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-repo-filterc' files

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to "import git_repo_filter"; however,
# since git style commands are dashed and git-repo-filter is used more
# as a tool than a library, renaming is not an option.
with open("../../../git-repo-filter") as f:
  repo_filter = imp.load_module('repo_filter', f, "git-repo-filter", ('.py', 'U', 1))

def my_commit_callback(commit):
  if commit.branch == "refs/heads/master":
    commit.branch = "refs/heads/develop"

args = repo_filter.FilteringOptions.default_options()
args.force = True
filter = repo_filter.RepoFilter(args, commit_callback = my_commit_callback)
filter.run()
