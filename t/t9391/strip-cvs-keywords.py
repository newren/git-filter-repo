#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.

Also, note that splicing repos may need some special care as fast-export
only shows the files that changed relative to the first parent, so there
may be gotchas if you are to splice near merge commits; this example does
not try to handle any such special cases.
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
