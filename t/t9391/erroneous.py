#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo
"""

import git_filter_repo as fr

def handle_tag(tag):
  print("Tagger: "+''.join(tag.tagger_name))

args = fr.FilteringOptions.parse_args(['--force', '--tag-callback', 'pass'])
filter = fr.RepoFilter(args, tag_callback = handle_tag)
filter.run()
