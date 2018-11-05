#!/usr/bin/env python

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to
#   import git_repo_filter
# However, since git style commands are dashed and git-filter-repo is used more
# as a tool than a library, renaming is not an option, so import is 5 lines:
import imp
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-filter-repoc' files
with open("../../../git-filter-repo") as f:
  repo_filter = imp.load_source('repo_filter', "git-filter-repo", f)
# End of convoluted import of git-filter-repo

def my_commit_callback(commit):
  if commit.branch == "refs/heads/master":
    commit.branch = "refs/heads/develop"

args = repo_filter.FilteringOptions.default_options()
args.force = True
filter = repo_filter.RepoFilter(args, commit_callback = my_commit_callback)
filter.run()
