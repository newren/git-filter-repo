Welcome to the community!

Contributions need to meet the bar for inclusion in git.git.  Although
filter-repo is not part of the git.git repository, I want to leave the
option open for it to be merged in the future.  As such, any
contributions need to follow the same [guidelines for contribution to
git.git](https://git.kernel.org/pub/scm/git/git.git/tree/Documentation/SubmittingPatches),
with a few exceptions:

  * While I
    [hate](https://public-inbox.org/git/CABPp-BG2SkH0GrRYpHLfp2Wey91ThwQoTgf9UmPa9f5Szn+v3Q@mail.gmail.com/)
    [GitHub](https://public-inbox.org/git/CABPp-BEcpasV4vBTm0uxQ4Vzm88MQAX-ArDG4e9QU8tEoNsZWw@mail.gmail.com/)
    [PRs](https://public-inbox.org/git/CABPp-BEHy8c3raHwf9aFXvXN0smf_WwCcNiYxQBwh7W6An60qQ@mail.gmail.com/)
    (as others point out, [it's mind-boggling in a bad way that
    web-based Git hosting and code review systems do such a poor
    job](http://nhaehnle.blogspot.com/2020/06/they-want-to-be-small-they-want-to-be.html)),
    git-format-patch and git-send-email can be a beast and I have not
    yet found time to modify Dscho's excellent
    [GitGitGadget](https://github.com/gitgitgadget/gitgitgadget) to
    work with git-filter-repo.  As such:
      * For very short single-commit changes, feel free to open GitHub PRs.
      * For more involved changes, if format-patch or send-email give you
        too much trouble, go ahead and open a GitHub PR and just mention
        that email didn't work out.
  * If emailing patches to the git list:
    * Include "filter-repo" at the start of the subject,
      e.g. "[filter-repo PATCH] Add packaging scripts for uploading to PyPI"
      instead of just "[PATCH] Add packaging scripts for uploading to PyPI"
    * CC me instead of the git maintainer
  * Git's [CodingGuidlines for python
    code](https://github.com/git/git/blob/v2.24.0/Documentation/CodingGuidelines#L482-L494)
    are only partially applicable:
    * python3 is a hard requirement; python2 is/was EOL at the end of
      2019 and should not be used.  (Commit 4d0264ab723c
      ("filter-repo: workaround python<2.7.9 exec bug", 2019-04-30)
      was the last version of filter-repo that worked with python2).
    * You can depend on anything in python 3.6 or earlier.  I may bump
      this minimum version over time, but do want to generally work
      with the python3 version found in current enterprise Linux
      distributions.
    * In filter-repo, it's not just OK to use bytestrings, you are
      expected to use them a lot.  Using unicode strings result in
      lots of ugly errors since input comes from filesystem names,
      commit messages, file contents, etc., none of which are
      guaranteed to be unicode.  (Plus unicode strings require lots of
      effort to verify, encode, and decode -- slowing the filtering
      process down).  I tried to work with unicode strings more
      broadly in the code base multiple times; but it's just a bad
      idea to use an abstraction that doesn't fit the data.
    * I generally like [PEP
      8](https://www.python.org/dev/peps/pep-0008/), but used
      two-space indents for years before learning of it and have just
      continued that habit.  For consistency, contributions should also
      use two-space indents and otherwise generally follow PEP 8.

There are a few extra things I would like folks to keep in mind:

  * Please test line coverage if you add or modify code

    * `make test` will run the testsuite under
      [coverage3](https://pypi.org/project/coverage/) (which you will
      need to install), and report on line coverage.  Line coverage of
      git-filter-repo needs to remain at 100%; line coverage of
      contrib and test scripts can be ignored.

  * Please do not be intimidated by detailed feedback:

    * In the git community, I have been contributing for years and
      have had hundreds of patches accepted but I still find that even
      when I try to make patches perfect I am not surprised when I
      have to spend as much or more time fixing up patches after
      submitting them than I did figuring out the patches in the first
      place.  git folks tend to do thorough reviews, which has taught
      me a lot, and I try to do the same for filter-repo.  Plus, as
      noted above, I want contributions from others to be acceptable
      in git.git itself.
