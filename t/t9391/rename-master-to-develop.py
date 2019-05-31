#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.
"""

import git_filter_repo as fr

def my_commit_callback(commit, metadata):
  if commit.branch == b"refs/heads/master":
    commit.branch = b"refs/heads/develop"

args = fr.FilteringOptions.default_options()
args.force = True
filter = fr.RepoFilter(args, commit_callback = my_commit_callback)
filter.run()
