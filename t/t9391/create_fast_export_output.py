#!/usr/bin/env python3

"""
Please see the
  ***** API BACKWARD COMPATIBILITY CAVEAT *****
near the top of git-filter-repo.
"""

import git_filter_repo as fr
from git_filter_repo import Blob, Reset, FileChange, Commit, Tag, FixedTimeZone
from git_filter_repo import Progress, Checkpoint

from datetime import datetime, timedelta

args = fr.FilteringOptions.default_options()
out = fr.RepoFilter(args)
out.importer_only()

world = Blob(b"Hello")
out.insert(world)

bar = Blob(b"foo\n")
out.insert(bar)

master = Reset(b"refs/heads/master")
out.insert(master)

changes = [FileChange(b'M', b'world', world.id, mode=b"100644"),
           FileChange(b'M', b'bar',   bar.id,   mode=b"100644")]
when = datetime(year=2005, month=4, day=7,
                hour=15, minute=16, second=10,
                tzinfo=FixedTimeZone(b"-0700"))
when_string = fr.date_to_string(when)
commit1 = Commit(b"refs/heads/master",
                 b"A U Thor", b"au@thor.email", when_string,
                 b"Com M. Iter", b"comm@iter.email", when_string,
                 b"My first commit!  Wooot!\n\nLonger description",
                 changes,
                 parents = [])
out.insert(commit1)

world = Blob(b"Hello\nHi")
out.insert(world)
world_link = Blob(b"world")
out.insert(world_link)

changes = [FileChange(b'M', b'world',  world.id,      mode=b"100644"),
           FileChange(b'M', b'planet', world_link.id, mode=b"120000")]
when += timedelta(days=3, hours=4, minutes=6)
when_string = fr.date_to_string(when)
commit2 = Commit(b"refs/heads/master",
                 b"A U Thor", b"au@thor.email", when_string,
                 b"Com M. Iter", b"comm@iter.email", when_string,
                 b"Make a symlink to world called planet, modify world",
                 changes,
                 parents = [commit1.id])
out.insert(commit2)

script = Blob(b"#!/bin/sh\n\necho Hello")
out.insert(script)
changes = [FileChange(b'M', b'runme', script.id, mode=b"100755"),
           FileChange(b'D', b'bar')]
when_string = b"1234567890 -0700"
commit3 = Commit(b"refs/heads/master",
                 b"A U Thor", b"au@thor.email", when_string,
                 b"Com M. Iter", b"comm@iter.email", when_string,
                 b"Add runme script, remove bar",
                 changes,
                 parents = [commit2.id])
out.insert(commit3)

progress = Progress(b"Done with the master branch now...")
out.insert(progress)
checkpoint = Checkpoint()
out.insert(checkpoint)

devel = Reset(b"refs/heads/devel", commit1.id)
out.insert(devel)

world = Blob(b"Hello\nGoodbye")
out.insert(world)

changes = [FileChange(b'DELETEALL'),
           FileChange(b'M', b'world', world.id, mode=b"100644"),
           FileChange(b'M', b'bar',   bar.id,   mode=b"100644")]
when = datetime(2006, 8, 17, tzinfo=FixedTimeZone(b"+0200"))
when_string = fr.date_to_string(when)
commit4 = Commit(b"refs/heads/devel",
                 b"A U Thor", b"au@thor.email", when_string,
                 b"Com M. Iter", b"comm@iter.email", when_string,
                 b"Modify world",
                 changes,
                 parents = [commit1.id])
out.insert(commit4)

world = Blob(b"Hello\nHi\nGoodbye")
out.insert(world)
when = fr.string_to_date(commit3.author_date) + timedelta(days=47)
when_string = fr.date_to_string(when)
# git fast-import requires file changes to be listed in terms of differences
# to the first parent.  Thus, despite the fact that runme and planet have
# not changed and bar was not modified in the devel side, we have to list them
# all anyway.
changes = [FileChange(b'M', b'world', world.id, mode=b"100644"),
           FileChange(b'D', b'bar'),
           FileChange(b'M', b'runme', script.id, mode=b"100755"),
           FileChange(b'M', b'planet', world_link.id, mode=b"120000")]

commit5 = Commit(b"refs/heads/devel",
                 b"A U Thor", b"au@thor.email", when_string,
                 b"Com M. Iter", b"comm@iter.email", when_string,
                 b"Merge branch 'master'\n",
                 changes,
                 parents = [commit4.id, commit3.id])
out.insert(commit5)


mytag = Tag(b"refs/tags/v1.0", commit5.id,
            b"His R. Highness", b"royalty@my.kingdom", when_string,
            b"I bequeath to my peons this royal software")
out.insert(mytag)
out.finish()
