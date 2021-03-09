from setuptools import setup
import os


def link_parent(src, target=None):
    if target is None:
        target = src
    try:
        os.symlink(os.path.join("..", src), target)
    except FileExistsError:
        pass


for f in ['git-filter-repo', 'README.md']:
    link_parent(f)

link_parent('git-filter-repo', 'git_filter_repo.py')


setup(use_scm_version=dict(root="..", relative_to=__file__),
      entry_points={'console_scripts': ['git-filter-repo = git_filter_repo:main']})
