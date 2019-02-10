#!/usr/bin/env python

import re
import git_filter_repo as fr

def strip_cvs_keywords(blob):
  # FIXME: Should first check if blob is a text file to avoid ruining
  # binaries.  Could use python.magic here, or just output blob.data to
  # the unix 'file' command
  pattern = r'\$(Id|Date|Source|Header|CVSHeader|Author|Revision):.*\$'
  replacement = r'$\1$'
  blob.data = re.sub(pattern, replacement, blob.data)

args = fr.FilteringOptions.parse_args(['--force'])
filter = fr.RepoFilter(args, blob_callback = strip_cvs_keywords)
filter.run()
