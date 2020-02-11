from setuptools import setup
import os
for f in ['git-filter-repo', 'git_filter_repo.py', 'README.md']:
    try:
        os.symlink("../"+f, f)
    except FileExistsError:
        pass
setup(use_scm_version=dict(root="..", relative_to=__file__))
