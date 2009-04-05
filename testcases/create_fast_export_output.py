#!/usr/bin/env python

import sys

from git_fast_filter import Blob, Reset, FileChanges, Commit, Tag
from git_fast_filter import Progress, Checkpoint, FixedTimeZone
from datetime import datetime, timedelta

output = sys.stdout

world = Blob("Hello")
world.dump(output)

bar = Blob("foo\n")
bar.dump(output)

master = Reset("refs/heads/master")
master.dump(output)

changes = [FileChanges('M', 'world', world.id, mode="100644"),
           FileChanges('M', 'bar',   bar.id,   mode="100644")]
when = datetime(year=2005, month=4, day=7,
                hour=15, minute=16, second=10,
                tzinfo=FixedTimeZone("-0700"))
commit1 = Commit("refs/heads/master",
                 "A U Thor", "au@thor.email", when,
                 "Com M. Iter", "comm@iter.email", when,
                 "My first commit!  Wooot!\n\nLonger description",
                 changes,
                 from_commit = None,
                 merge_commits = [])
commit1.dump(output)

world = Blob("Hello\nHi")
world.dump(output)
world_link = Blob("world")
world_link.dump(output)

changes = [FileChanges('M', 'world',  world.id,      mode="100644"),
           FileChanges('M', 'planet', world_link.id, mode="120000")]
when += timedelta(days=3, hours=4, minutes=6)
commit2 = Commit("refs/heads/master",
                 "A U Thor", "au@thor.email", when,
                 "Com M. Iter", "comm@iter.email", when,
                 "Make a symlink to world called planet, modify world",
                 changes,
                 from_commit = commit1.id,
                 merge_commits = [])
commit2.dump(output)

script = Blob("#!/bin/sh\n\necho Hello")
script.dump(output)
changes = [FileChanges('M', 'runme', script.id, mode="100755"),
           FileChanges('D', 'bar')]
when = datetime.fromtimestamp(timestamp=1234567890, tz=FixedTimeZone("-0700"))
commit3 = Commit("refs/heads/master",
                 "A U Thor", "au@thor.email", when,
                 "Com M. Iter", "comm@iter.email", when,
                 "Add runme script, remove bar",
                 changes,
                 from_commit = commit2.id,
                 merge_commits = [])
commit3.dump(output)

progress = Progress("Done with the master branch now...")
progress.dump(output)
checkpoint = Checkpoint()
checkpoint.dump(output)

devel = Reset("refs/heads/devel", commit1.id)
devel.dump(output)

world = Blob("Hello\nGoodbye")
world.dump(output)

changes = [FileChanges('M', 'world', world.id, mode="100644")]
when = datetime(2006, 8, 17, tzinfo=FixedTimeZone("+0200"))
commit4 = Commit("refs/heads/devel",
                 "A U Thor", "au@thor.email", when,
                 "Com M. Iter", "comm@iter.email", when,
                 "Modify world",
                 changes,
                 from_commit = commit1.id,
                 merge_commits = [])
commit4.dump(output)

world = Blob("Hello\nHi\nGoodbye")
world.dump(output)
when = commit3.author_date + timedelta(days=47)
# git fast-import requires file changes to be listed in terms of differences
# to the first parent.  Thus, despite the fact that runme and planet have
# not changed and bar was not modified in the devel side, we have to list them
# all anyway.
changes = [FileChanges('M', 'world', world.id, mode="100644"),
           FileChanges('D', 'bar'),
           FileChanges('M', 'runme', script.id, mode="100755"),
           FileChanges('M', 'planet', world_link.id, mode="120000")]

commit5 = Commit("refs/heads/devel",
                 "A U Thor", "au@thor.email", when,
                 "Com M. Iter", "comm@iter.email", when,
                 "Merge branch 'master'\n",
                 changes,
                 from_commit = commit4.id,
                 merge_commits = [commit3.id])
commit5.dump(output)


mytag = Tag("refs/tags/v1.0", commit5.id,
            "His R. Highness", "royalty@my.kingdom", when,
            "I bequeath to my peons this royal software")
mytag.dump(output)
