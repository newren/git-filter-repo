from setuptools import setup
import os
for f in ['git-filter-repo', 'git_filter_repo.py', 'README.md']:
  os.symlink("../"+f, f)
setup(use_scm_version=dict(root="..", relative_to=__file__))
