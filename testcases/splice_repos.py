#!/usr/bin/env python

import re
import sys

from git_fast_filter import Reset, Commit, FastExportFilter, record_id_rename
from git_fast_filter import fast_export_output, fast_import_input

class InterleaveRepositories:
  def __init__(self, repo1, repo2, output_dir):
    self.repo1 = repo1
    self.repo2 = repo2
    self.output_dir = output_dir

    self.commit_map = {}
    self.last_commit = None

  def skip_reset(self, reset):
    reset.skip()

  def hold_commit(self, commit):
    commit.skip(new_id = commit.id)
    letter = re.match('Commit (.)', commit.message).group(1)
    self.commit_map[letter] = commit

  def weave_commit(self, commit):
    letter = re.match('Commit (.)', commit.message).group(1)
    prev_letter = chr(ord(letter)-1)

    # Splice in any extra commits needed
    if prev_letter in self.commit_map:
      new_commit = self.commit_map[prev_letter]
      new_commit.from_commit = self.last_commit
      new_commit.dump(self.target.stdin)
      commit.from_commit = new_commit.id

    # Dump our commit now
    commit.dump(self.target.stdin)

    # Make sure that commits that depended on new_commit.id will now depend
    # on commit.id
    if prev_letter in self.commit_map:
      self.last_commit = commit.id
      record_id_rename(new_commit.id, commit.id, handle_transitivity = True)

  def run(self):
    self.target = fast_import_input(self.output_dir)

    input1 = fast_export_output(self.repo1)
    filter1 = FastExportFilter(reset_callback  = lambda r: self.skip_reset(r),
                               commit_callback = lambda c: self.hold_commit(c))
    filter1.run(input1.stdout, self.target.stdin)

    input2 = fast_export_output(self.repo2)
    filter2 = FastExportFilter(commit_callback = lambda c: self.weave_commit(c))
    filter2.run(input2.stdout, self.target.stdin)

    # Wait for git-fast-import to complete (only necessary since we passed
    # file objects to FastExportFilter.run; and even then the worst that
    # happens is git-fast-import completes after this python script does)
    self.target.stdin.close()
    self.target.wait()

splicer = InterleaveRepositories(sys.argv[1], sys.argv[2], sys.argv[3])
splicer.run()
