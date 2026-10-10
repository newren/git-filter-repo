https://github.com/cp794001/git-filter-repo/blob/main2/pyproject.toml#!/usr/bin/env python3

"""
git-filter-repo filters git repositories, similar to git filter-branch, BFG
repo cleaner, and others.  The basic idea is that it works by running
   git fast-export <options> | filter | git fast-import <options>
where this program not only launches the whole pipeline but also serves as
the 'filter' in the middle.  It does a few additional things on top as well
in order to make it into a well-rounded filtering tool.

git-filter-repo can also be used as a library for more involved filtering
operations; however:
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
  Programs using git-filter-repo as a library can reach pretty far into its
  internals, but I am not prepared to guarantee backward compatibility of
  all APIs.  I suspect changes will be rare, but I reserve the right to
  change any API.  Since it is assumed that repository filtering is
  something one would do very rarely, and in particular that it's a
  one-shot operation, this should not be a problem in practice for anyone.
  However, if you want to re-use a program you have written that uses
  git-filter-repo as a library (or makes use of one of its --*-callback
  arguments), you should either make sure you are using the same version of
  git and git-filter-repo, or make sure to re-test it.

  If there are particular pieces of the API you are concerned about, and
  there is not already a testcase for it in t9391-lib-usage.sh or
  t9392-python-callback.sh, please contribute a testcase.  That will not
  prevent me from changing the API, but it will allow you to look at the
  history of a testcase to see whether and how the API changed.
  ***** END API BACKWARD COMPATIBILITY CAVEAT *****
"""

import argparse
import collections
import fnmatch
import gettext
import io
import os
import platform
import re
import shutil
import subprocess
import sys
import time
import textwrap

from datetime import tzinfo, timedelta, datetime

__all__ = ["Blob", "Reset", "FileChange", "Commit", "Tag", "Progress",
           "Checkpoint", "FastExportParser", "ProgressWriter",
           "string_to_date", "date_to_string",
           "record_id_rename", "GitUtils", "FilteringOptions", "RepoFilter"]

# The globals to make visible to callbacks. They will see all our imports for
# free, as well as our public API.
public_globals = ["__builtins__", "argparse", "collections", "fnmatch",
                  "gettext", "io", "os", "platform", "re", "shutil",
                  "subprocess", "sys", "time", "textwrap", "tzinfo",
                  "timedelta", "datetime"] + __all__

deleted_hash = b'0'*40
write_marks = True
date_format_permissive = True

def gettext_poison(msg):
  if "GIT_TEST_GETTEXT_POISON" in os.environ: # pragma: no cover
    return "# GETTEXT POISON #"
  return gettext.gettext(msg)

_ = gettext_poison

def setup_gettext():
  TEXTDOMAIN="git-filter-repo"
  podir = os.environ.get("GIT_TEXTDOMAINDIR") or "@@LOCALEDIR@@"
  if not os.path.isdir(podir): # pragma: no cover
    podir = None  # Python has its own fallback; use that

  ## This looks like the most straightforward translation of the relevant
  ## code in git.git:gettext.c and git.git:perl/Git/I18n.pm:
  #import locale
  #locale.setlocale(locale.LC_MESSAGES, "");
  #locale.setlocale(locale.LC_TIME, "");
  #locale.textdomain(TEXTDOMAIN);
  #locale.bindtextdomain(TEXTDOMAIN, podir);
  ## but the python docs suggest using the gettext module (which doesn't
  ## have setlocale()) instead, so:
  gettext.textdomain(TEXTDOMAIN);
  gettext.bindtextdomain(TEXTDOMAIN, podir);

def _timedelta_to_seconds(delta):
  """
  Converts timedelta to seconds
  """
  offset = delta.days*86400 + delta.seconds + (delta.microseconds+0.0)/1000000
  return round(offset)

class FixedTimeZone(tzinfo):
  """
  Fixed offset in minutes east from UTC.
  """

  tz_re = re.compile(br'^([-+]?)(\d\d)(\d\d)$')

  def __init__(self, offset_string):
    tzinfo.__init__(self)
    sign, hh, mm = FixedTimeZone.tz_re.match(offset_string).groups()
    factor = -1 if (sign and sign == b'-') else 1
    self._offset = timedelta(minutes = factor*(60*int(hh) + int(mm)))
    self._offset_string = offset_string

  def utcoffset(self, dt):
    return self._offset

  def tzname(self, dt):
    return self._offset_string

  def dst(self, dt):
    return timedelta(0)

def string_to_date(datestring):
  (unix_timestamp, tz_offset) = datestring.split()
  return datetime.fromtimestamp(int(unix_timestamp),
                                FixedTimeZone(tz_offset))

def date_to_string(dateobj):
  epoch = datetime.fromtimestamp(0, dateobj.tzinfo)
  return(b'%d %s' % (int(_timedelta_to_seconds(dateobj - epoch)),
                     dateobj.tzinfo.tzname(0)))

def decode(bytestr):
  'Try to convert bytestr to utf-8 for outputting as an error message.'
  return bytestr.decode('utf-8', 'backslashreplace')

def glob_to_regex(glob_bytestr):
  'Translate glob_bytestr into a regex on bytestrings'

  # fnmatch.translate is idiotic and won't accept bytestrings
  if (decode(glob_bytestr).encode() != glob_bytestr): # pragma: no cover
    raise SystemExit(_("Error: Cannot handle glob %s").format(glob_bytestr))

  # Create regex operating on string
  regex = fnmatch.translate(decode(glob_bytestr))

  # FIXME: This is an ugly hack...
  # fnmatch.translate tries to do multi-line matching and wants the glob to
  # match up to the end of the input, which isn't relevant for us, so we
  # have to modify the regex.  fnmatch.translate has used different regex
  # constructs to achieve this with different python versions, so we have
  # to check for each of them and then fix it up.  It would be much better
  # if fnmatch.translate could just take some flags to allow us to specify
  # what we want rather than employing this hackery, but since it
  # doesn't...
  if regex.endswith(r'\Z(?ms)'): # pragma: no cover
    regex = regex[0:-7]
  elif regex.startswith(r'(?s:') and regex.endswith(r')\Z'): # pragma: no cover
    regex = regex[4:-3]
  elif regex.startswith(r'(?s:') and regex.endswith(r')\z'): # pragma: no cover
    # Yaay, python3.14 for senselessly duplicating \Z as \z...
    regex = regex[4:-3]

  # Finally, convert back to regex operating on bytestr
  return regex.encode()

class PathQuoting:
  _unescape = {b'a': b'\a',
               b'b': b'\b',
               b'f': b'\f',
               b'n': b'\n',
               b'r': b'\r',
               b't': b'\t',
               b'v': b'\v',
               b'"': b'"',
               b'\\':b'\\'}
  _unescape_re = re.compile(br'\\([a-z"\\]|[0-9]{3})')
  _escape = [bytes([x]) for x in range(127)]+[
             b'\\'+bytes(ord(c) for c in oct(x)[2:]) for x in range(127,256)]
  _reverse = dict(map(reversed, _unescape.items()))
  for x in _reverse:
    _escape[ord(x)] = b'\\'+_reverse[x]
  _special_chars = [len(x) > 1 for x in _escape]

  @staticmethod
  def unescape_sequence(orig):
    seq = orig.group(1)
    return PathQuoting._unescape[seq] if len(seq) == 1 else bytes([int(seq, 8)])

  @staticmethod
  def dequote(quoted_string):
    if quoted_string.startswith(b'"'):
      assert quoted_string.endswith(b'"')
      return PathQuoting._unescape_re.sub(PathQuoting.unescape_sequence,
                                          quoted_string[1:-1])
    return quoted_string

  @staticmethod
  def enquote(unquoted_string):
    # Option 1: Quoting when fast-export would:
    #    pqsc = PathQuoting._special_chars
    #    if any(pqsc[x] for x in set(unquoted_string)):
    # Option 2, perf hack: do minimal amount of quoting required by fast-import
    if unquoted_string.startswith(b'"') or b'\n' in unquoted_string:
      pqe = PathQuoting._escape
      return b'"' + b''.join(pqe[x] for x in unquoted_string) + b'"'
    return unquoted_string

class AncestryGraph(object):
  """
  A class that maintains a direct acycle graph of commits for the purpose of
  determining if one commit is the ancestor of another.

  A note about identifiers in Commit objects:
    * Commit objects have 2 identifiers: commit.old_id and commit.id, because:
    * The original fast-export stream identified commits by an identifier.
      This is often an integer, but is sometimes a hash (particularly when
      --reference-excluded-parents is provided)
    * The new fast-import stream we use may not use the same identifiers.
      If new blobs or commits are inserted (such as lint-history does), then
      the integer (or hash) are no longer valid.

  A note about identifiers in AncestryGraph objects, of which there are three:
    * A given AncestryGraph is based on either commit.old_id or commit.id, but
      not both.  These are the keys for self.value.
    * Using full hashes (occasionally) for children in self.graph felt
      wasteful, so we use our own internal integer within self.graph.
      self.value maps from commit {old_}id to our internal integer id.
    * When working with commit.old_id, it is also sometimes useful to be able
      to map these to the original hash, i.e. commit.original_id.  So, we
      also have self.git_hash for mapping from commit.old_id to git's commit
      hash.
  """

  def __init__(self):
    # The next internal identifier we will use; increments with every commit
    # added to the AncestryGraph
    self.cur_value = 0

    # A mapping from the external identifiers given to us to the simple integers
    # we use in self.graph
    self.value = {}

    # A tuple of (depth, list-of-ancestors).  Values and keys in this graph are
    # all integers from the (values of the) self.value dict.  The depth of a
    # commit is one more than the max depth of any of its ancestors.
    self.graph = {}

    # A mapping from external identifier (i.e. from the keys of self.value) to
    # the hash of the given commit.  Only populated for graphs based on
    # commit.old_id, since we won't know until later what the git_hash for
    # graphs based on commit.id (since we have to wait for fast-import to
    # create the commit and notify us of its hash; see _pending_renames).
    # elsewhere
    self.git_hash = {}

    # Reverse maps; only populated if needed.  Caller responsible to check
    # and ensure they are populated
    self._reverse_value = {}
    self._hash_to_id = {}

    # Cached results from previous calls to is_ancestor().
    self._cached_is_ancestor = {}

  def record_external_commits(self, external_commits):
    """
    Record in graph that each commit in external_commits exists, and is
    treated as a root commit with no parents.
    """
    for c in external_commits:
      if c not in self.value:
        self.cur_value += 1
        self.value[c] = self.cur_value
        self.graph[self.cur_value] = (1, [])
        self.git_hash[c] = c

  def add_commit_and_parents(self, commit, parents, githash = None):
    """
    Record in graph that commit has the given parents (all identified by
    fast export stream identifiers, usually integers but sometimes hashes).
    parents _MUST_ have been first recorded.  commit _MUST_ not have been
    recorded yet.  Also, record the mapping between commit and githash, if
    githash is given.
    """
    assert all(p in self.value for p in parents)
    assert commit not in self.value

    # Get values for commit and parents
    self.cur_value += 1
    self.value[commit] = self.cur_value
    if githash:
      self.git_hash[commit] = githash
    graph_parents = [self.value[x] for x in parents]

    # Determine depth for commit, then insert the info into the graph
    depth = 1
    if parents:
      depth += max(self.graph[p][0] for p in graph_parents)
    self.graph[self.cur_value] = (depth, graph_parents)

  def record_hash(self, commit_id, githash):
    '''
    If a githash was not recorded for commit_id, when add_commit_and_parents
    was called, add it now.
    '''
    assert commit_id in self.value
    assert commit_id not in self.git_hash
    self.git_hash[commit_id] = githash

  def _ensure_reverse_maps_populated(self):
    if not self._hash_to_id:
      assert not self._reverse_value
      self._hash_to_id = {v: k for k, v in self.git_hash.items()}
      self._reverse_value = {v: k for k, v in self.value.items()}

  def get_parent_hashes(self, commit_hash):
    '''
    Given a commit_hash, return its parents hashes
    '''
    #
    # We have to map:
    #    commit hash -> fast export stream id -> graph id
    # then lookup
    #    parent graph ids for given graph id
    # then we need to map
    #    parent graph ids -> parent fast export ids -> parent commit hashes
    #
    self._ensure_reverse_maps_populated()
    commit_fast_export_id = self._hash_to_id[commit_hash]
    commit_graph_id = self.value[commit_fast_export_id]
    parent_graph_ids = self.graph[commit_graph_id][1]
    parent_fast_export_ids = [self._reverse_value[x] for x in parent_graph_ids]
    parent_hashes = [self.git_hash[x] for x in parent_fast_export_ids]
    return parent_hashes

  def map_to_hash(self, commit_id):
    '''
    Given a commit (by fast export stream id), return its hash
    '''
    return self.git_hash.get(commit_id, None)

  def is_ancestor(self, possible_ancestor, check):
    """
    Return whether possible_ancestor is an ancestor of check
    """
    a, b = self.value[possible_ancestor], self.value[check]
    original_pair = (a,b)
    a_depth = self.graph[a][0]
    ancestors = [b]
    visited = set()
    while ancestors:
      ancestor = ancestors.pop()
      prev_pair = (a, ancestor)
      if prev_pair in self._cached_is_ancestor:
        if not self._cached_is_ancestor[prev_pair]:
          continue
        self._cached_is_ancestor[original_pair] = True
        return True
      if ancestor in visited:
        continue
      visited.add(ancestor)
      depth, more_ancestors = self.graph[ancestor]
      if ancestor == a:
        self._cached_is_ancestor[original_pair] = True
        return True
      elif depth <= a_depth:
        continue
      ancestors.extend(more_ancestors)
    self._cached_is_ancestor[original_pair] = False
    return False

class MailmapInfo(object):
  def __init__(self, filename):
    self.changes = {}
    self._parse_file(filename)

  def _parse_file(self, filename):
    name_and_email_re = re.compile(br'(.*?)\s*<([^>]*)>\s*')
    comment_re = re.compile(br'\s*#.*')
    if not os.access(filename, os.R_OK):
      raise SystemExit(_("Cannot read %s") % decode(filename))
    with open(filename, 'br') as f:
      count = 0
      for line in f:
        count += 1
        err = "Unparseable mailmap file: line #{} is bad: {}".format(count, line)
        # Remove comments
        line = comment_re.sub(b'', line)
        # Remove leading and trailing whitespace
        line = line.strip()
        if not line:
          continue

        m = name_and_email_re.match(line)
        if not m:
          raise SystemExit(err)
        proper_name, proper_email = m.groups()
        if len(line) == m.end():
          self.changes[(None, proper_email)] = (proper_name, proper_email)
          continue
        rest = line[m.end():]
        m = name_and_email_re.match(rest)
        if m:
          commit_name, commit_email = m.groups()
          if len(rest) != m.end():
            raise SystemExit(err)
        else:
          commit_name, commit_email = rest, None
        self.changes[(commit_name, commit_email)] = (proper_name, proper_email)

  def translate(self, name, email):
    ''' Given a name and email, return the expected new name and email from the
        mailmap if there is a translation rule for it, otherwise just return
        the given name and email.'''
    for old, new in self.changes.items():
      old_name, old_email = old
      new_name, new_email = new
      if (old_email is None or email.lower() == old_email.lower()) and (
          name == old_name or not old_name):
        return (new_name or name, new_email or email)
    return (name, email)

class ProgressWriter(object):
  def __init__(self):
    self._last_progress_update = time.time()
    self._last_message = None

  def show(self, msg):
    self._last_message = msg
    now = time.time()
    if now - self._last_progress_update > .1:
      self._last_progress_update = now
      sys.stdout.write("\r{}".format(msg))
      sys.stdout.flush()

  def finish(self):
    self._last_progress_update = 0
    if self._last_message:
      self.show(self._last_message)
    sys.stdout.write("\n")

class _IDs(object):
  """
  A class that maintains the 'name domain' of all the 'marks' (short int
  id for a blob/commit git object). There are two reasons this mechanism
  is necessary:
    (1) the output text of fast-export may refer to an object using a different
        mark than the mark that was assigned to that object using IDS.new().
        (This class allows you to translate the fast-export marks, "old" to
         the marks assigned from IDS.new(), "new").
    (2) when we prune a commit, its "old" id becomes invalid.  Any commits
        which had that commit as a parent needs to use the nearest unpruned
        ancestor as its parent instead.

  Note that for purpose (1) above, this typically comes about because the user
  manually creates Blob or Commit objects (for insertion into the stream).
  It could also come about if we attempt to read the data from two different
  repositories and trying to combine the data (git fast-export will number ids
  from 1...n, and having two 1's, two 2's, two 3's, causes issues; granted, we
  this scheme doesn't handle the two streams perfectly either, but if the first
  fast export stream is entirely processed and handled before the second stream
  is started, this mechanism may be sufficient to handle it).
  """

  def __init__(self):
    """
    Init
    """
    # The id for the next created blob/commit object
    self._next_id = 1

    # A map of old-ids to new-ids (1:1 map)
    self._translation = {}

    # A map of new-ids to every old-id that points to the new-id (1:N map)
    self._reverse_translation = {}

  def has_renames(self):
    """
    Return whether there have been ids remapped to new values
    """
    return bool(self._translation)

  def new(self):
    """
    Should be called whenever a new blob or commit object is created. The
    returned value should be used as the id/mark for that object.
    """
    rv = self._next_id
    self._next_id += 1
    return rv

  def record_rename(self, old_id, new_id, handle_transitivity = False):
    """
    Record that old_id is being renamed to new_id.
    """
    if old_id != new_id or old_id in self._translation:
      # old_id -> new_id
      self._translation[old_id] = new_id

      # Transitivity will be needed if new commits are being inserted mid-way
      # through a branch.
      if handle_transitivity:
        # Anything that points to old_id should point to new_id
        if old_id in self._reverse_translation:
          for id_ in self._reverse_translation[old_id]:
            self._translation[id_] = new_id

      # Record that new_id is pointed to by old_id
      if new_id not in self._reverse_translation:
        self._reverse_translation[new_id] = []
      self._reverse_translation[new_id].append(old_id)

  def translate(self, old_id):
    """
    If old_id has been mapped to an alternate id, return the alternate id.
    """
    if old_id in self._translation:
      return self._translation[old_id]
    else:
      return old_id

  def __str__(self):
    """
    Convert IDs to string; used for debugging
    """
    rv = "Current count: %d\nTranslation:\n" % self._next_id
    for k in sorted(self._translation):
      rv += "  %d -> %s\n" % (k, self._translation[k])

    rv += "Reverse translation:\n"
    reverse_keys = list(self._reverse_translation.keys())
    if None in reverse_keys: # pragma: no cover
      reverse_keys.remove(None)
      reverse_keys = sorted(reverse_keys)
      reverse_keys.append(None)
    for k in reverse_keys:
      rv += "  " + str(k) + " -> " + str(self._reverse_translation[k]) + "\n"

    return rvdelta.secondsfnmatch.translateedf8dac05da88d9a42389ad19a6d096dcae12c3egit filter-repo is a versatile tool for rewriting history, which includes
[capabilities I have not found anywhere
else](#design-rationale-behind-filter-repo).  It roughly falls into the
same space of tool as [git
filter-branch](https://git-scm.com/docs/git-filter-branch) but without the
capitulation-inducing poor
[performance](https://public-inbox.org/git/CABPp-BGOz8nks0+Tdw5GyGqxeYR-3FF6FT5JcgVqZDYVRQ6qog@mail.gmail.com/),
with far more capabilities, and with a design that scales usability-wise
beyond trivial rewriting cases.  [git filter-repo is now recommended by the
git project](https://git-scm.com/docs/git-filter-branch#_warning) instead
of git filter-branch.

While most users will probably just use filter-repo as a simple command
line tool (and likely only use a few of its flags), at its core filter-repo
contains a library for creating history rewriting tools.  As such, users
with specialized needs can leverage it to quickly create [entirely new
history rewriting tools](contrib/filter-repo-demos).

# Table of Contents

  * [Prerequisites](#prerequisites)
  * [How do I install it?](#how-do-i-install-it)
  * [How do I use it?](#how-do-i-use-it)
  * [Why filter-repo instead of other alternatives?](#why-filter-repo-instead-of-other-alternatives)
    * [filter-branch](#filter-branch)
    * [BFG Repo Cleaner](#bfg-repo-cleaner)
  * [Simple example, with comparisons](#simple-example-with-comparisons)
    * [Solving this with filter-repo](#solving-this-with-filter-repo)
    * [Solving this with BFG Repo Cleaner](#solving-this-with-bfg-repo-cleaner)
    * [Solving this with filter-branch](#solving-this-with-filter-branch)
    * [Solving this with fast-export/fast-import](#solving-this-with-fast-exportfast-import)
  * [Design rationale behind filter-repo](#design-rationale-behind-filter-repo)
  * [How do I contribute?](#how-do-i-contribute)
  * [Is there a Code of Conduct?](#is-there-a-code-of-conduct)
  * [Upstream Improvements](#upstream-improvements)

# Prerequisites

filter-repo requires:

  * git >= 2.36.0
  * python3 >= 3.6

# How do I install it?

While the `git-filter-repo` repository has many files, the main logic
is all contained in a single-file python script named
`git-filter-repo`, which was done to make installation for basic use
on many systems trivial: just place that one file into your $PATH.

See [INSTALL.md](INSTALL.md) for things beyond basic usage or special
cases.  The more involved instructions are only needed if one of the
following apply:

  * you do not find the above comment about trivial installation intuitively
    obvious
  * you are working with a python3 executable named something other than
    "python3"
  * you want to install documentation (beyond the builtin docs shown with -h)
  * you want to run some of the [contrib](contrib/filter-repo-demos/) examples
  * you want to create your own python filtering scripts using filter-repo as
    a module/library

# How do I use it?

For comprehensive documentation:
  * see the [user manual](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html)
  * alternative formating of the user manual is available on various
    external sites
    ([example](https://www.mankier.com/1/git-filter-repo)), for those
    that don't like the htmlpreview.github.io layout, though it may
    only be up-to-date as of the latest release

If you prefer learning from examples:
  * there is a [cheat sheet for converting filter-branch
    commands](Documentation/converting-from-filter-branch.md#cheat-sheet-conversion-of-examples-from-the-filter-branch-manpage),
    which covers every example from the filter-branch manual
  * there is a [cheat sheet for converting BFG Repo Cleaner
    commands](Documentation/converting-from-bfg-repo-cleaner.md#cheat-sheet-conversion-of-examples-from-bfg),
    which covers every example from the BFG website
  * the [simple example](#simple-example-with-comparisons) below may
    be of interest
  * the user manual has an extensive [examples
section](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html#EXAMPLES)
  * I have collected a set of [example filterings based on user-filed issues](Documentation/examples-from-user-filed-issues.md)

In either case, you may also find the [Frequently Answered Questions](Documentation/FAQ.md) useful.

# Why filter-repo instead of other alternatives?

This was covered in more detail in a [Git Rev News article on
filter-repo](https://git.github.io/rev_news/2019/08/21/edition-54/#an-introduction-to-git-filter-repo--written-by-elijah-newren),
but some highlights for the main competitors:

## filter-branch

  * filter-branch is [extremely to unusably
    slow](https://public-inbox.org/git/CABPp-BGOz8nks0+Tdw5GyGqxeYR-3FF6FT5JcgVqZDYVRQ6qog@mail.gmail.com/)
    ([multiple orders of magnitude slower than it should
    be](https://git-scm.com/docs/git-filter-branch#PERFORMANCE))
    for non-trivial repositories.

  * [filter-branch is riddled with
    gotchas](https://git-scm.com/docs/git-filter-branch#SAFETY) that can
    silently corrupt your rewrite or at least thwart your "cleanup"
    efforts by giving you something more problematic and messy than what
    you started with.

  * filter-branch is [very onerous](#simple-example-with-comparisons)
    [to
    use](https://github.com/newren/git-filter-repo/blob/a6a6a1b0f62d365bbe2e76f823e1621857ec4dbd/contrib/filter-repo-demos/filter-lamely#L9-L61)
    for any rewrite which is even slightly non-trivial.

  * the git project has stated that the above issues with filter-branch
    cannot be backward compatibly fixed; they recommend that you [stop
    using
    filter-branch](https://git-scm.com/docs/git-filter-branch#_warning)

  * die-hard fans of filter-branch may be interested in
    [filter-lamely](contrib/filter-repo-demos/filter-lamely)
    (a.k.a. [filter-branch-ish](contrib/filter-repo-demos/filter-branch-ish)),
    a reimplementation of filter-branch based on filter-repo which is
    more performant (though not nearly as fast or safe as
    filter-repo).

  * a [cheat
    sheet](Documentation/converting-from-filter-branch.md#cheat-sheet-conversion-of-examples-from-the-filter-branch-manpage)
    is available showing how to convert example commands from the manual of
    filter-branch into filter-repo commands.

## BFG Repo Cleaner

  * great tool for its time, but while it makes some things simple, it
    is limited to a few kinds of rewrites.

  * its architecture is not amenable to handling more types of
    rewrites.

  * its architecture presents some shortcomings and bugs even for its
    intended usecase.

  * fans of bfg may be interested in
    [bfg-ish](contrib/filter-repo-demos/bfg-ish), a reimplementation of bfg
    based on filter-repo which includes several new features and bugfixes
    relative to bfg.

  * a [cheat
    sheet](Documentation/converting-from-bfg-repo-cleaner.md#cheat-sheet-conversion-of-examples-from-bfg)
    is available showing how to convert example commands from the manual of
    BFG Repo Cleaner into filter-repo commands.

# Simple example, with comparisons

Let's say that we want to extract a piece of a repository, with the intent
on merging just that piece into some other bigger repo.  For extraction, we
want to:

  * extract the history of a single directory, src/.  This means that only
    paths under src/ remain in the repo, and any commits that only touched
    paths outside this directory will be removed.
  * rename all files to have a new leading directory, my-module/ (e.g. so that
    src/foo.c becomes my-module/src/foo.c)
  * rename any tags in the extracted repository to have a 'my-module-'
    prefix (to avoid any conflicts when we later merge this repo into
    something else)

## Solving this with filter-repo

Doing this with filter-repo is as simple as the following command:
```shell
  git filter-repo --path src/ --to-subdirectory-filter my-module --tag-rename '':'my-module-'
```
(the single quotes are unnecessary, but make it clearer to a human that we
are replacing the empty string as a prefix with `my-module-`)

## Solving this with BFG Repo Cleaner

BFG Repo Cleaner is not capable of this kind of rewrite; in fact, all
three types of wanted changes are outside of its capabilities.

## Solving this with filter-branch

filter-branch comes with a pile of caveats (more on that below) even
once you figure out the necessary invocation(s):

```shell
  git filter-branch \
      --tree-filter 'mkdir -p my-module && \
                     git ls-files \
                         | grep -v ^src/ \
                         | xargs git rm -f -q && \
                     ls -d * \
                         | grep -v my-module \
                         | xargs -I files mv files my-module/' \
          --tag-name-filter 'echo "my-module-$(cat)"' \
	  --prune-empty -- --all
  git clone file://$(pwd) newcopy
  cd newcopy
  git for-each-ref --format="delete %(refname)" refs/tags/ \
      | grep -v refs/tags/my-module- \
      | git update-ref --stdin
  git gc --prune=now
```

Some might notice that the above filter-branch invocation will be really
slow due to using --tree-filter; you could alternatively use the
--index-filter option of filter-branch, changing the above commands to:

```shell
  git filter-branch \
      --index-filter 'git ls-files \
                          | grep -v ^src/ \
                          | xargs git rm -q --cached;
                      git ls-files -s \
                          | sed "s%$(printf \\t)%&my-module/%" \
                          | git update-index --index-info;
                      git ls-files \
                          | grep -v ^my-module/ \
                          | xargs git rm -q --cached' \
      --tag-name-filter 'echo "my-module-$(cat)"' \
      --prune-empty -- --all
  git clone file://$(pwd) newcopy
  cd newcopy
  git for-each-ref --format="delete %(refname)" refs/tags/ \
      | grep -v refs/tags/my-module- \
      | git update-ref --stdin
  git gc --prune=now
```

However, for either filter-branch command there are a pile of caveats.
First, some may be wondering why I list five commands here for
filter-branch.  Despite the use of --all and --tag-name-filter, and
filter-branch's manpage claiming that a clone is enough to get rid of
old objects, the extra steps to delete the other tags and do another
gc are still required to clean out the old objects and avoid mixing
new and old history before pushing somewhere.  Other caveats:
  * Commit messages are not rewritten; so if some of your commit
    messages refer to prior commits by (abbreviated) sha1, after the
    rewrite those messages will now refer to commits that are no longer
    part of the history.  It would be better to rewrite those
    (abbreviated) sha1 references to refer to the new commit ids.
  * The --prune-empty flag sometimes misses commits that should be
    pruned, and it will also prune commits that *started* empty rather
    than just ended empty due to filtering.  For repositories that
    intentionally use empty commits for versioning and publishing
    related purposes, this can be detrimental.
  * The commands above are OS-specific.  GNU vs. BSD issues for sed,
    xargs, and other commands often trip up users; I think I failed to
    get most folks to use --index-filter since the only example in the
    filter-branch manpage that both uses it and shows how to move
    everything into a subdirectory is linux-specific, and it is not
    obvious to the reader that it has a portability issue since it
    silently misbehaves rather than failing loudly.
  * The --index-filter version of the filter-branch command may be two to
    three times faster than the --tree-filter version, but both
    filter-branch commands are going to be multiple orders of magnitude
    slower than filter-repo.
  * Both commands assume all filenames are composed entirely of ascii
    characters (even special ascii characters such as tabs or double
    quotes will wreak havoc and likely result in missing files or
    misnamed files)

## Solving this with fast-export/fast-import

One can kind of hack this together with something like:

```shell
  git fast-export --no-data --reencode=yes --mark-tags --fake-missing-tagger \
      --signed-tags=strip --tag-of-filtered-object=rewrite --all \
      | grep -vP '^M [0-9]+ [0-9a-f]+ (?!src/)' \
      | grep -vP '^D (?!src/)' \
      | perl -pe 's%^(M [0-9]+ [0-9a-f]+ )(.*)$%\1my-module/\2%' \
      | perl -pe 's%^(D )(.*)$%\1my-module/\2%' \
      | perl -pe s%refs/tags/%refs/tags/my-module-% \
      | git -c core.ignorecase=false fast-import --date-format=raw-permissive \
            --force --quiet
  git for-each-ref --format="delete %(refname)" refs/tags/ \
      | grep -v refs/tags/my-module- \
      | git update-ref --stdin
  git reset --hard
  git reflog expire --expire=now --all
  git gc --prune=now
```

But this comes with some nasty caveats and limitations:
  * The various greps and regex replacements operate on the entire
    fast-export stream and thus might accidentally corrupt unintended
    portions of it, such as commit messages.  If you needed to edit
    file contents and thus dropped the --no-data flag, it could also
    end up corrupting file contents.
  * This command assumes all filenames in the repository are composed
    entirely of ascii characters, and also exclude special characters
    such as tabs or double quotes.  If such a special filename exists
    within the old src/ directory, it will be pruned even though it
    was intended to be kept.  (In slightly different repository
    rewrites, this type of editing also risks corrupting filenames
    with special characters by adding extra double quotes near the end
    of the filename and in some leading directory name.)
  * This command will leave behind huge numbers of useless empty
    commits, and has no realistic way of pruning them.  (And if you
    tried to combine this technique with another tool to prune the
    empty commits, then you now have no way to distinguish between
    commits which were made empty by the filtering that you want to
    remove, and commits which were empty before the filtering process
    and which you thus may want to keep.)
  * Commit messages which reference other commits by hash will now
    reference old commits that no longer exist.  Attempting to edit
    the commit messages to update them is extraordinarily difficult to
    add to this kind of direct rewrite.

# Design rationale behind filter-repo

None of the existing repository filtering tools did what I wanted;
they all came up short for my needs. No tool provided any of the
first eight traits below I wanted, and no tool provided more than
two of the last four traits either:

  1. [Starting report] Provide user an analysis of their repo to help
     them get started on what to prune or rename, instead of expecting
     them to guess or find other tools to figure it out.  (Triggered, e.g.
     by running the first time with a special flag, such as --analyze.)

  1. [Keep vs. remove] Instead of just providing a way for users to
     easily remove selected paths, also provide flags for users to
     only *keep* certain paths.  Sure, users could workaround this by
     specifying to remove all paths other than the ones they want to
     keep, but the need to specify all paths that *ever* existed in
     **any** version of the repository could sometimes be quite
     painful.  For filter-branch, using pipelines like `git ls-files |
     grep -v ... | xargs -r git rm` might be a reasonable workaround
     but can get unwieldy and isn't as straightforward for users; plus
     those commands are often operating-system specific (can you spot
     the GNUism in the snippet I provided?).

  1. [Renaming] It should be easy to rename paths.  For example, in
     addition to allowing one to treat some subdirectory as the root
     of the repository, also provide options for users to make the
     root of the repository just become a subdirectory.  And more
     generally allow files and directories to be easily renamed.
     Provide sanity checks if renaming causes multiple files to exist
     at the same path.  (And add special handling so that if a commit
     merely copied oldname->newname without modification, then
     filtering oldname->newname doesn't trigger the sanity check and
     die on that commit.)

  1. [More intelligent safety] Writing copies of the original refs to
     a special namespace within the repo does not provide a
     user-friendly recovery mechanism.  Many would struggle to recover
     using that.  Almost everyone I've ever seen do a repository
     filtering operation has done so with a fresh clone, because
     wiping out the clone in case of error is a vastly easier recovery
     mechanism.  Strongly encourage that workflow by [detecting and
     bailing if we're not in a fresh
     clone](https://htmlpreview.github.io/?https://github.com/newren/git-filter-repo/blob/docs/html/git-filter-repo.html#FRESHCLONE),
     unless the user overrides with --force.

  1. [Auto shrink] Automatically remove old cruft and repack the
     repository for the user after filtering (unless overridden); this
     simplifies things for the user, helps avoid mixing old and new
     history together, and avoids problems where the multi-step
     process for shrinking the repo documented in the manpage doesn't
     actually work in some cases.  (I'm looking at you,
     filter-branch.)

  1. [Clean separation] Avoid confusing users (and prevent accidental
     re-pushing of old stuff) due to mixing old repo and rewritten
     repo together.  (This is particularly a problem with filter-branch
     when using the --tag-name-filter option, and sometimes also an
     issue when only filtering a subset of branches.)

  1. [Versatility] Provide the user the ability to extend the tool or
     even write new tools that leverage existing capabilities, and
     provide this extensibility in a way that (a) avoids the need to
     fork separate processes (which would destroy performance), (b)
     avoids making the user specify OS-dependent shell commands (which
     would prevent users from sharing commands with each other), (c)
     takes advantage of rich data structures (because hashes, dicts,
     lists, and arrays are prohibitively difficult in shell) and (d)
     provides reasonable string manipulation capabilities (which are
     sorely lacking in shell).

  1. [Old commit references] Provide a way for users to use old commit
     IDs with the new repository (in particular via mapping from old to
     new hashes with refs/replace/ references).

  1. [Commit message consistency] If commit messages refer to other
     commits by ID (e.g. "this reverts commit 01234567890abcdef", "In
     commit 0013deadbeef9a..."), those commit messages should be
     rewritten to refer to the new commit IDs.

  1. [Become-empty pruning] Commits which become empty due to filtering
     should be pruned.  If the parent of a commit is pruned, the first
     non-pruned ancestor needs to become the new parent.  If no
     non-pruned ancestor exists and the commit was not a merge, then it
     becomes a new root commit.  If no non-pruned ancestor exists and
     the commit was a merge, then the merge will have one less parent
     (and thus make it likely to become a non-merge commit which would
     itself be pruned if it had no file changes of its own).  One
     special thing to note here is that we prune commits which become
     empty, NOT commits which start empty.  Some projects intentionally
     create empty commits for versioning or publishing reasons, and
     these should not be removed.  (As a special case, commits which
     started empty but whose parent was pruned away will also be
     considered to have "become empty".)

  1. [Become-degenerate pruning] Pruning of commits which become empty
     can potentially cause topology changes, and there are lots of
     special cases.  Normally, merge commits are not removed since they
     are needed to preserve the graph topology, but the pruning of
     parents and other ancestors can ultimately result in the loss of
     one or more parents.  A simple case was already noted above: if a
     merge commit loses enough parents to become a non-merge commit and
     it has no file changes, then it too can be pruned.  Merge commits
     can also have a topology that becomes degenerate: it could end up
     with the merge_base serving as both parents (if all intervening
     commits from the original repo were pruned), or it could end up
     with one parent which is an ancestor of its other parent.  In such
     cases, if the merge has no file changes of its own, then the merge
     commit can also be pruned.  However, much as we do with empty
     pruning we do not prune merge commits that started degenerate
     (which indicates it may have been intentional, such as with --no-ff
     merges) but only merge commits that become degenerate and have no
     file changes of their own.

  1. [Speed] Filtering should be reasonably fast

# How do I contribute?

See the [contributing guidelines](Documentation/Contributing.md).

# Is there a Code of Conduct?

Participants in the filter-repo community are expected to adhere to
the same standards as for the git project, so the [git Code of
Conduct](https://git.kernel.org/pub/scm/git/git.git/tree/CODE_OF_CONDUCT.md)
applies.

# Upstream Improvements

Work on filter-repo and [its
predecessor](https://public-inbox.org/git/51419b2c0904072035u1182b507o836a67ac308d32b9@mail.gmail.com/)
has also driven numerous improvements to fast-export and fast-import
(and occasionally other commands) in core git, based on things
filter-repo needs to do its work:

  * git-2.48.0
    * [fast-import: disallow more path components](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=da91a90c2f)
    * [fast-import: disallow "." and ".." path components](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=4a2790a257)
    * [fast-import: avoid making replace refs point to themselves](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=5e904f1a4a)
  * git-2.28.0
    * [fast-import: add new --date-format=raw-permissive format](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d42a2fb72f)
  * git-2.24.0
    * [fast-export: handle nested tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=941790d7de)
    * [t9350: add tests for tags of things other than a commit](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=8d7d33c1ce)
    * [fast-export: allow user to request tags be marked with --mark-tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=a1638cfe12)
    * [fast-export: add support for --import-marks-if-exists](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=208d69246e)
    * [fast-import: add support for new 'alias' command](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=b8f50e5b60)
    * [fast-import: allow tags to be identified by mark labels](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=f73b2aba05)
    * [fast-import: fix handling of deleted tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=3164e6bd24)
    * [fast-export: fix exporting a tag and nothing else](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=af2abd870b)
    * [git-fast-import.txt: clarify that multiple merge commits are allowed](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d1387d3895)
  * git-2.23.0
    * [t9350: fix encoding test to actually test reencoding](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=32615ce762)
    * [fast-import: support 'encoding' commit header](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=3edfcc65fd)
    * [fast-export: avoid stripping encoding header if we cannot reencode](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=ccbfc96dc4)
    * [fast-export: differentiate between explicitly UTF-8 and implicitly
      UTF-8](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=57a8be2cb0)
    * [fast-export: do automatic reencoding of commit messages only if
      requested](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=e80001f8fd)
  * git-2.22.0
    * [log,diff-tree: add --combined-all-paths option](
        https://git.kernel.org/pub/scm/git/git.git/commit/?id=d76ce4f734)
    * [t9300: demonstrate bug with get-mark and empty orphan commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=62edbec7de)
    * [git-fast-import.txt: fix wording about where ls command can appear](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=a63c54a019)
    * [fast-import: check most prominent commands first](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=5056bb7646)
    * [fast-import: only allow cat-blob requests where it makes sense](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=7ffde293f2)
    * [fast-import: fix erroneous handling of get-mark with empty orphan
      commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=cf7b857a77)
    * [Honor core.precomposeUnicode in more places](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=8e712ef6fc)
  * git-2.21.0
    * [fast-export: convert sha1 to oid](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=843b9e6d48)
    * [git-fast-import.txt: fix documentation for --quiet option](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=f55c979b14)
    * [git-fast-export.txt: clarify misleading documentation about rev-list
      args](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=4532be7cba)
    * [fast-export: use value from correct enum](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=b93b81e799)
    * [fast-export: avoid dying when filtering by paths and old tags exist](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=1f30c904b3)
    * [fast-export: move commit rewriting logic into a function for reuse](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=f129c4275c)
    * [fast-export: when using paths, avoid corrupt stream with non-existent
      mark](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=cd13762d8f)
    * [fast-export: ensure we export requested refs](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=fdf31b6369)
    * [fast-export: add --reference-excluded-parents option](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=530ca19c02)
    * [fast-import: remove unmaintained duplicate documentation](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=25dd3e4889)
    * [fast-export: add a --show-original-ids option to show
      original names](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=a965bb3116)
    * [git-show-ref.txt: fix order of flags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=bd8d6f0def)
  * git-2.20.0
    * [update-ref: fix type of update_flags variable to
      match its usage](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=e4c34855a2)
    * [update-ref: allow --no-deref with --stdin](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d345e9fbe7)
  * git-1.7.3
    * [fast-export: Fix dropping of files with --import-marks and path
      limiting](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=4087a02e45)
    * [fast-export: Add a --full-tree option](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=7f40ab0916)
    * [fast-export: Fix output order of D/F changes](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=060df62422)
    * [fast-import: Improve robustness when D->F changes provided in wrong
      order](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=253fb5f889)
  * git-1.6.4:
    * [fast-export: Set revs.topo_order before calling setup_revisions](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=668f3aa776)
    * [fast-export: Omit tags that tag trees](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=02c48cd69b)
    * [fast-export: Make sure we show actual ref names instead of "(null)"](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=2374502c6c)
    * [fast-export: Do parent rewriting to avoid dropping relevant commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=32164131db)
    * [fast-export: Add a --tag-of-filtered-object option for newly
      dangling tags](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=2d8ad46919)
    * [Add new fast-export testcases](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=25e0ca5dd6)
    * [fast-export: Document the fact that git-rev-list arguments are
      accepted](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=8af15d282e)
  * git-1.6.3:
    * [git-filter-branch: avoid collisions with variables in eval'ed
      commands](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=d5b0c97d13)
    * [Correct missing SP characters in grammar comment at top of
      fast-import.c](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=98e1a4186a)
    * [fast-export: Avoid dropping files from commits](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=ebeec7dbc5)
  * git-1.6.1.4:
    * [fast-export: ensure we traverse commits in topological order](
      https://git.kernel.org/pub/scm/git/git.git/commit/?id=784f8affe4)
