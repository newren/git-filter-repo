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
import sys
import git_filter_repo as fr

class InterleaveRepositories:
  def __init__(self, repo1, repo2, output_dir):
    self.repo1 = repo1
    self.repo2 = repo2
    self.output_dir = output_dir

    self.commit_map = {}
    self.last_commit = None

  def skip_reset(self, reset, metadata):
    reset.skip()

  def hold_commit(self, commit, metadata):
    commit.skip(new_id = commit.id)
    letter = re.match(b'Commit (.)', commit.message).group(1)
    self.commit_map[letter] = commit

  def weave_commit(self, commit, metadata):
    letter = re.match(b'Commit (.)', commit.message).group(1)
    prev_letter = bytes([ord(letter)-1])

    # Splice in any extra commits needed
    if prev_letter in self.commit_map:
      new_commit = self.commit_map[prev_letter]
      new_commit.dumped = 0
      new_commit.parents = [self.last_commit] if self.last_commit else []
      # direct_insertion=True to avoid weave_commit being called recursively
      # on the same commit
      self.out.insert(new_commit, direct_insertion = True)
      commit.parents = [new_commit.id]

    # Dump our commit now
    self.out.insert(commit, direct_insertion = True)

    # Make sure that commits that depended on new_commit.id will now depend
    # on commit.id
    if prev_letter in self.commit_map:
      self.last_commit = commit.id
      fr.record_id_rename(new_commit.id, commit.id)

  def run(self):
    blob = fr.Blob(b'public gpg key contents')
    tag = fr.Tag(b'gpg-pubkey', blob.id,
                 b'Ima Tagger', b'ima@tagg.er', b'1136199845 +0300',
                 b'Very important explanation and stuff')

    args = fr.FilteringOptions.parse_args(['--target', self.output_dir])
    out = fr.RepoFilter(args)
    out.importer_only()
    self.out = out

    i1args = fr.FilteringOptions.parse_args(['--source', self.repo1])
    i1 = fr.RepoFilter(i1args,
                       reset_callback  = self.skip_reset,
                       commit_callback = self.hold_commit)
    i1.set_output(out)
    i1.run()

    i2args = fr.FilteringOptions.parse_args(['--source', self.repo2])
    i2 = fr.RepoFilter(i2args,
                       commit_callback = self.weave_commit)
    i2.set_output(out)
    i2.run()

    out.insert(blob)
    out.insert(tag)
    out.finish()

splicer = InterleaveRepositories(sys.argv[1], sys.argv[2], sys.argv[3])
splicer.run()
