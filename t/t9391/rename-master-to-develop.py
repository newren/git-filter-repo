#!/usr/bin/env python

import git_filter_repo as fr

def my_commit_callback(commit):
  if commit.branch == "refs/heads/master":
    commit.branch = "refs/heads/develop"

args = fr.FilteringOptions.default_options()
args.force = True
filter = fr.RepoFilter(args, commit_callback = my_commit_callback)
filter.run()
