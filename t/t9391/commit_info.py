#!/usr/bin/env python

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo
"""

import re
import datetime

import git_filter_repo as fr

def change_up_them_commits(commit):
  # Change the commit author
  if commit.author_name == "Copy N. Paste":
    commit.author_name = "Ima L. Oser"
    commit.author_email = "aloser@my.corp"

  # Fix the author email
  commit.author_email = re.sub("@my.crp", "@my.corp", commit.author_email)

  # Fix the committer date (bad timezone conversion in initial import)
  oldtime = fr.string_to_date(commit.committer_date)
  newtime = oldtime + datetime.timedelta(hours=-5)
  commit.committer_date = fr.date_to_string(newtime)

  # Fix the commit message
  commit.message = re.sub("Marketing is staffed with pansies", "",
                          commit.message)

args = fr.FilteringOptions.parse_args(['--force'])
filter = fr.RepoFilter(args, commit_callback = change_up_them_commits)
filter.run()
