#!/usr/bin/env python

import re
import imp
import sys
sys.dont_write_bytecode = True # .pyc generation -> ugly 'git-repo-filterc' files

# python makes importing files with dashes hard, sorry.  Renaming would
# allow us to simplify this to "import git_repo_filter"; however,
# since git style commands are dashed and git-repo-filter is used more
# as a tool than a library, renaming is not an option.
with open("../../../git-repo-filter") as f:
  repo_filter = imp.load_module('repo_filter', f, "git-repo-filter", ('.py', 'U', 1))

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
