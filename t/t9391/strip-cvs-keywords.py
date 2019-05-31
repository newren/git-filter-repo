#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.
"""

import re
import git_filter_repo as fr

def strip_cvs_keywords(blob, metadata):
  # FIXME: Should first check if blob is a text file to avoid ruining
  # binaries.  Could use python.magic here, or just output blob.data to
  # the unix 'file' command
  pattern = br'\$(Id|Date|Source|Header|CVSHeader|Author|Revision):.*\$'
  replacement = br'$\1$'
  blob.data = re.sub(pattern, replacement, blob.data)

args = fr.FilteringOptions.parse_args(['--force'])
filter = fr.RepoFilter(args, blob_callback = strip_cvs_keywords)
filter.run()
