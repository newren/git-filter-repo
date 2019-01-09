#!/usr/bin/env python

import imp
import os
import re
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-repo-filterc' files

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to "import git_repo_filter"; however,
# since git style commands are dashed and git-repo-filter is used more
# as a tool than a library, renaming is not an option.
with open("../../../git-repo-filter") as f:
  #repo_filter = imp.load_module('repo_filter', f, "git-repo-filter", ('.py', 'U', 1))
  repo_filter = imp.load_source('repo_filter', "git-repo-filter", f)

#for x in os.environ.get("PYTHONPATH", '.').split(':'):
#  modpath = os.path.join(x, "git-fast-filter")
#  if os.path.exists(modpath):
#    with open(modpath) as f:
#      repo_filter = imp.load_module('repo_filter', f, modpath, ('.py', 'U', 1))
#    break

from datetime import datetime, timedelta

def change_up_them_commits(commit):
  # Change the commit author
  if commit.author_name == "Copy N. Paste":
    commit.author_name = "Ima L. Oser"
    commit.author_email = "aloser@my.corp"

  # Fix the author email
  commit.author_email = re.sub("@my.crp", "@my.corp", commit.author_email)

  # Fix the committer date (bad timezone conversion in initial import)
  commit.committer_date += timedelta(hours=-5)

  # Fix the commit message
  commit.message = re.sub("Marketing is staffed with pansies", "",
                          commit.message)

args = repo_filter.FilteringOptions.parse_args(['--force'])
filter = repo_filter.RepoFilter(args, commit_callback = change_up_them_commits)
filter.run()
