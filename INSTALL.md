#!/usr/bin/env python3

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

    return rv# Table of Contents

  * [Pre-requisites](#pre-requisites)
  * [Simple Installation](#simple-installation)
  * [Installation via Package Manager](#installation-via-package-manager)
  * [Detailed installation explanation for
     packagers](#detailed-installation-explanation-for-packagers)
  * [Installation as Python Package from
     PyPI](#installation-as-python-package-from-pypi)
  * [Installation via Makefile](#installation-via-makefile)
  * [Notes for Windows Users](#notes-for-windows-users)

# Pre-requisites

Instructions on this page assume you have already installed both
[Git](https://git-scm.com) and [Python](https://www.python.org/)
(though the [Notes for Windows Users](#notes-for-windows-users) has
some tips on Python).

# Simple Installation

All you need to do is download one file: the [git-filter-repo script
in this repository](git-filter-repo) ([direct link to raw
file](https://raw.githubusercontent.com/newren/git-filter-repo/main/git-filter-repo)),
making sure to preserve its name (`git-filter-repo`, with no
extension).  **That's it**.  You're done.

Then you can run any command you want, such as

    $ python3 git-filter-repo --analyze

If you place the git-filter-repo script in your $PATH, then you can
shorten commands by replacing `python3 git-filter-repo` with `git
filter-repo`; the manual assumes this but you can use the longer form.

Optionally, if you also want to use some of the contrib scripts, then
you need to make sure you have a `git_filter_repo.py` file which is
either a link to or copy of `git-filter-repo`, and you need to place
that git_filter_repo.py file in $PYTHONPATH.

If you prefer an "official" installation over the manual installation
explained above, the other sections may have useful tips.

# Installation via Package Manager

If you want to install via some [package
manager](https://alternativeto.net/software/yellowdog-updater-modified/?license=opensource),
you can run

    $ PACKAGE_TOOL install git-filter-repo

The following package managers have packaged git-filter-repo:

[![Packaging status](https://repology.org/badge/vertical-allrepos/git-filter-repo.svg)](https://repology.org/project/git-filter-repo/versions)

This list covers at least Windows (Scoop), Mac OS X (Homebrew), and
Linux (most the rest).  Note that I do not curate this list (and have
no interest in doing so); https://repology.org tracks who packages
these versions.

# Detailed installation explanation for packagers

filter-repo only consists of a few files that need to be installed:

  * git-filter-repo

    This is the _only_ thing needed for basic use.

    This can be installed in the directory pointed to by `git --exec-path`,
    or placed anywhere in $PATH.

    If your python3 executable is named "python" instead of "python3"
    (this particularly appears to affect a number of Windows users),
    then you'll also need to modify the first line of git-filter-repo
    to replace "python3" with "python".

  * git_filter_repo.py

    This is needed if you want to make use of one of the scripts in
    contrib/filter-repo-demos/, or want to write your own script making use
    of filter-repo as a python library.

    You can create this symlink to (or copy of) git-filter-repo named
    git_filter_repo.py and place it in your python site packages; `python
    -c "import site; print(site.getsitepackages())"` may help you find the
    appropriate location for your system.  Alternatively, you can place
    this file anywhere within $PYTHONPATH.

  * git-filter-repo.1

    This is needed if you want `git filter-repo --help` to succeed in
    displaying the manpage, when help.format is "man" (the default on Linux
    and Mac).

    This can be installed in the directory pointed to by `$(git
    --man-path)/man1/`, or placed anywhere in $MANDIR/man1/ where $MANDIR
    is some entry from $MANPATH.

    Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the manpage is installed.

  * git-filter-repo.html

    This is needed if you want `git filter-repo --help` to succeed in
    displaying the html version of the help, when help.format is set to
    "html" (the default on Windows).

    This can be installed in the directory pointed to by `git --html-path`.

    Note that `git filter-repo -h` will show a more limited built-in set of
    instructions regardless of whether the html version of help is
    installed.

So, installation might look something like the following:

1. If you don't have the necessary documentation files (because you
   are installing from a clone of filter-repo instead of from a
   tarball) then you can first run:

   `make snag_docs`

   (which just copies the generated documentation files from the
   `docs` branch)

2. Run the following

   ```
   cp -a git-filter-repo $(git --exec-path)
   cp -a git-filter-repo.1 $(git --man-path)/man1 && mandb
   cp -a git-filter-repo.html $(git --html-path)
   ln -s $(git --exec-path)/git-filter-repo \
       $(python -c "import site; print(site.getsitepackages()[-1])")/git_filter_repo.py
   ```

or you can use the provided Makefile, as noted below.

# Installation as Python Package from PyPI

`git-filter-repo` is also available as
[PyPI-package](https://pypi.org/project/git-filter-repo/).

Therefore, it can be installed with [pipx](https://pypa.github.io/pipx/)
or [uv tool](https://docs.astral.sh/uv/concepts/tools/).
Command example for pipx:

`pipx install git-filter-repo`

# Installation via Makefile

Installing should be doable by hand, but a Makefile is provided for those
that prefer it.  However, usage of the Makefile really requires overriding
at least a couple of the directories with sane values, e.g.

    $ make prefix=/usr pythondir=/usr/lib64/python3.8/site-packages install

Also, the Makefile will not edit the shebang line (the first line) of
git-filter-repo if your python executable is not named "python3";
you'll still need to do that yourself.

# Notes for Windows Users

git-filter-repo can be installed with multiple tools, such as
[pipx](https://pypa.github.io/pipx/) or a Windows-specific package manager
like Scoop (both of which were covered above).

Sadly, Windows sometimes makes things difficult.  Common and historical issues:

  * **Non-functional Python stub**: Windows apparently ships with a
    [non-functional
    python](https://github.com/newren/git-filter-repo/issues/36#issuecomment-568933825).
    This can even manifest as [the app
    hanging](https://github.com/newren/git-filter-repo/issues/36) or
    [the system appearing to
    hang](https://github.com/newren/git-filter-repo/issues/312).  Try
    installing
    [Python](https://docs.microsoft.com/en-us/windows/python/beginners)
    from the [Microsoft
    Store](https://apps.microsoft.com/store/search?publisher=Python%20Software%20Foundation)
  * **Modifying PATH, making the script executable**: If modifying your PATH
    and/or making scripts executable is difficult for you, you can skip that
    step by just using `python3 git-filter-repo` instead of `git filter-repo`
    in your commands.
  * **Different python executable name**:  Some users don't have
    a `python3` executable but one named something else like `python`
    or `python3.8` or whatever.  You may need to edit the first line
    of the git-filter-repo script to specify the appropriate path.  Or
    just don't bother and instead use the long form for executing
    filter-repo commands.  Namely, replace the `git filter-repo` part
    of commands with `PYTHON_EXECUTABLE git-filter-repo`. (Where
    `PYTHON_EXECUTABLE` is something like `python` or `python3.8` or
    `C:\PATH\TO\INSTALLATION\OF\python3.exe` or whatever).
  * **Symlink issues**:  git_filter_repo.py is supposed to be a symlink to
    git-filter-repo, so that it appears to have identical contents.
    If your system messed up the symlink (usually meaning it looks like a
    regular file with just one line), then delete git_filter_repo.py and
    replace it with a copy of git-filter-repo.
  * **Old GitBash limitations**: older versions of GitForWindows had an
    unfortunate shebang length limitation (see [git-for-windows issue
    #3165](https://github.com/git-for-windows/git/pull/3165)).  If
    you're affected, just use the long form for invoking filter-repo
    commands, i.e. replace the `git filter-repo` part of commands with
    `python3 git-filter-repo`.

For additional historical context, see:
  * [#371](https://github.com/newren/git-filter-repo/issues/371#issuecomment-1267116186)
  * [#360](https://github.com/newren/git-filter-repo/issues/360#issuecomment-1276813596)
  * [#312](https://github.com/newren/git-filter-repo/issues/312)
  * [#307](https://github.com/newren/git-filter-repo/issues/307)
  * [#225](https://github.com/newren/git-filter-repo/pull/225)
  * [#231](https://github.com/newren/git-filter-repo/pull/231)
  * [#124](https://github.com/newren/git-filter-repo/issues/124)
  * [#36](https://github.com/newren/git-filter-repo/issues/36)
  * [this git mailing list
     thread](https://lore.kernel.org/git/nycvar.QRO.7.76.6.2004251610300.18039@tvgsbejvaqbjf.bet/)
