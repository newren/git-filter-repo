#!/usr/bin/env python

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to
#   import git_repo_filter
# However, since git style commands are dashed and git-filter-repo is used more
# as a tool than a library, renaming is not an option, so import is 5 lines:
import imp
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-filter-repoc' files
with open("../../../git-filter-repo") as f:
  repo_filter = imp.load_source('repo_filter', "git-filter-repo", f)
# End of convoluted import of git-filter-repo

import re

def strip_cvs_keywords(blob):
  # FIXME: Should first check if blob is a text file to avoid ruining
  # binaries.  Could use python.magic here, or just output blob.data to
  # the unix 'file' command
  pattern = r'\$(Id|Date|Source|Header|CVSHeader|Author|Revision):.*\$'
  replacement = r'$\1$'
  blob.data = re.sub(pattern, replacement, blob.data)

args = repo_filter.FilteringOptions.parse_args(['--force'])
filter = repo_filter.RepoFilter(args, blob_callback = strip_cvs_keywords)
filter.run()
