#!/usr/bin/env python

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo
"""

import git_filter_repo as fr

def handle_tag(tag):
  print("Decipher this: "+''.join(reversed(progress.message)))

args = fr.FilteringOptions.parse_args(['--force', '--tag-callback', 'pass'])
filter = fr.RepoFilter(args, tag_callback = handle_tag)
filter.run()
