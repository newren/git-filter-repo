#!/usr/bin/env python

from git_fast_filter import Blob, Reset, FileChanges, Commit, FastExportFilter
from datetime import datetime, timdelta

def change_up_them_commits(commit):
  # Change the commit author
  if commit.author == "Copy N. Paste":
    commit.author = "Ima L. Oser"
    commit.author_email = "aloser@my.corp"

  # Fix the author email
  commit.author_email = re.sub("@my.crp", "@my.corp", commit.author_email)

  # Fix the committer date (bad timezone conversion in initial import)
  commit.committer_date += timedelta(hours=-5)

  # Fix the commit message
  commit.message = re.sub("Marketing is staffed with pansies", "",
                          commit.message)

filter = FastExportFilter(commit_callback = change_up_them_commits)
filter.run()
