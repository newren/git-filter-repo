#!/usr/bin/env python

from git_fast_filter import Blob, Reset, FileChanges, Commit, FastExportFilter

def my_commit_callback(commit):
  if commit.branch == "refs/heads/master":
    commit.branch = "refs/heads/slave"

filter = FastExportFilter(commit_callback = my_commit_callback)
filter.run()
