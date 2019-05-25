#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo
"""

import re
import datetime

import git_filter_repo as fr

def change_up_them_commits(commit, metadata):
  # Change the commit author
  if commit.author_name == b"Copy N. Paste":
    commit.author_name = b"Ima L. Oser"
    commit.author_email = b"aloser@my.corp"

  # Fix the author email
  commit.author_email = re.sub(b"@my.crp", b"@my.corp", commit.author_email)

  # Fix the committer date (bad timezone conversion in initial import)
  oldtime = fr.string_to_date(commit.committer_date)
  newtime = oldtime + datetime.timedelta(hours=-5)
  commit.committer_date = fr.date_to_string(newtime)

  # Fix the commit message
  commit.message = re.sub(b"Marketing is staffed with pansies", b"",
                          commit.message)

args = fr.FilteringOptions.parse_args(['--force'])
filter = fr.RepoFilter(args, commit_callback = change_up_them_commits)
filter.run()
