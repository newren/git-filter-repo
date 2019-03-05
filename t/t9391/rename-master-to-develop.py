#!/usr/bin/env python

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.

Also, note that splicing repos may need some special care as fast-export
only shows the files that changed relative to the first parent, so there
may be gotchas if you are to splice near merge commits; this example does
not try to handle any such special cases.
"""

import git_filter_repo as fr

def my_commit_callback(commit):
  if commit.branch == "refs/heads/master":
    commit.branch = "refs/heads/develop"

args = fr.FilteringOptions.default_options()
args.force = True
filter = fr.RepoFilter(args, commit_callback = my_commit_callback)
filter.run()
