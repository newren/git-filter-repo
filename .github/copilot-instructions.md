# git-filter-repo AI Coding Agent Guidelines

## Project Overview
git-filter-repo is a high-performance git history rewriting tool built as a single-file Python script. It's designed as both a CLI tool and a reusable library for specialized filtering operations. The project prioritizes raw performance and works by piping `git fast-export` output through custom filters to `git fast-import`.

## Architecture

### Core Design Pattern: Fast-Export Pipeline
All history rewriting follows this pattern:
```
git fast-export <options> | [this tool filters] | git fast-import <options>
```
The main script (`git-filter-repo`) serves as the filter in the middle. Key classes:
- **FastExportParser**: Parses fast-export output into Python objects (Blob, Commit, Tag, Reset, FileChange)
- **RepoFilter**: Orchestrates the entire filtering pipeline with callbacks
- **FilteringOptions**: Command-line argument parsing and configuration

### Single-File Distribution
The executable `git-filter-repo` and library module `git_filter_repo.py` are the **same file**. Installation is trivial (copy to PATH). For library usage, create a symlink: `git_filter_repo.py -> git-filter-repo`.

### Object Model (Fast-Export Elements)
All git objects inherit from `_GitElement` or `_GitElementWithId`:
- **Blob, Commit, Tag**: Contain marks (internal IDs) for reference tracking
- **FileChange**: Represents file modifications within commits (inline data or blob references)
- **Reset, Checkpoint**: Branch/ref management and sanity checks
- Objects are **bytestrings** by design—never unicode (see Converting section)

### Critical Pattern: ID Management
The `_IDs` class maps old fast-export marks to new marks because:
1. Manual object creation assigns different marks than fast-export output
2. Pruned commits require parent remapping to nearest unpruned ancestor
3. Multi-repo merging needs consistent mark namespacing

## Developer Workflows

### Running Tests
```bash
make test
# or directly:
t/run_tests
```
- Tests run under **coverage3**; line coverage must stay at 100% for git-filter-repo.py
- Test scripts are bash (t/t9390*.sh) using test-lib.sh framework
- Test data in t/t9390/, t9391/, t9393/, t9394/ directories
- PYTHONPATH is set to include parent dir; `PRETEND_UNICODE_ARGS=1` forces bytestring handling

### Key Test Structure
- **t9390-filter-repo-basics.sh**: Path filtering, renaming, message/author rewriting
- **t9391-filter-repo-lib-usage.sh**: Library API usage with custom callbacks
- **t9392-filter-repo-python-callback.sh**: Python callback functions
- **t9393-filter-repo-rerun.sh**: Rerun detection and LFS handling
- Test data repos in t/t9390/, expected outputs inline

### Building & Installing
```bash
make build      # No-op (pure Python)
make install    # Installs git-filter-repo, docs, creates symlink
make snag_docs  # Pulls docs from origin/docs branch
```

## Coding Conventions

### Bytestring vs Unicode (Critical!)
**ALWAYS use bytestrings for git data.** Unicode breaks in this codebase because:
- File paths, commit messages, email addresses come from git (binary-safe)
- Filesystem paths may not be valid UTF-8
- The codebase has `PRETEND_UNICODE_ARGS=1` test flag to catch violations

Prefix bytestrings with `b`, e.g.:
```python
b"filename.txt"
b"author@example.com"
commit.message = re.sub(b"old", b"new", commit.message)
```

### Two-Space Indentation
Code uses 2-space indents (pre-PEP 8 convention, maintained for consistency). Follow this strictly.

### Callback Functions Pattern
Callbacks receive objects by reference and modify in-place. They're **not** isolated; changes directly affect the output.

Example (from contrib examples):
```python
def change_up_them_commits(commit, metadata):
  if commit.author_name == b"Copy N. Paste":
    commit.author_name = b"Ima L. Oser"
    commit.author_email = b"aloser@my.corp"
  commit.message = re.sub(b"old", b"new", commit.message)

args = fr.FilteringOptions.parse_args(['--force'])
filter = fr.RepoFilter(args, commit_callback=change_up_them_commits)
filter.run()
```

### Path Filtering Rules
- Paths **cannot start with `/`** (enforced in AppendFilter)
- Rename paths must match slash endings (both end with `/` or neither does)
- Invalid components `.` and `..` are rejected
- Glob patterns auto-extend: `dir/file` becomes `dir/file*` if not a glob

## Integration Points

### External Dependencies
- **git >= 2.36.0**: Required for fast-export/fast-import
- **python3 >= 3.6**: Core requirement (pyproject.toml, supported through 3.12)
- **subprocess**: For git command execution (via SubprocessWrapper)
- **argparse**: CLI parsing
- **gettext**: i18n support (optional)

### Public API (from __all__)
```python
["Blob", "Reset", "FileChange", "Commit", "Tag", "Progress",
 "Checkpoint", "FastExportParser", "ProgressWriter",
 "string_to_date", "date_to_string",
 "record_id_rename", "GitUtils", "FilteringOptions", "RepoFilter"]
```
Only these are guaranteed stable. Internal APIs may change (see backward compatibility caveat in git-filter-repo header).

### Date Handling
- Use `string_to_date()` to parse git dates (handles timezones)
- Use `date_to_string()` for output
- Works with `datetime.timedelta` for adjustments (see barebones-example)

## Common Tasks

### Adding a New Filter
1. Add argument to FilteringOptions.create_arg_parser() with help text
2. Store parsed value in FilteringOptions namespace
3. In RepoFilter, add logic to check the option and apply filtering
4. Add test cases to t9390-filter-repo-basics.sh or appropriate test file
5. Ensure 100% line coverage

### Modifying Commit Metadata
Use the `commit_callback` parameter to RepoFilter:
```python
def my_callback(commit, metadata):
  commit.author_name = ...
  commit.message = ...
  # FileChange objects in commit.file_changes
```

### Library vs CLI Mode
- **CLI**: User runs `git-filter-repo [OPTIONS]`
- **Library**: User imports as `git_filter_repo` and instantiates RepoFilter
- RepoAnalyze mode (--analyze) is a read-only variant

## Documentation & Examples

- **README.md**: High-level overview, comparisons to filter-branch/BFG
- **INSTALL.md**: Installation variants
- **Documentation/**: User manual, conversion guides, FAQ, contributing guidelines
- **contrib/filter-repo-demos/**: Example scripts (barebones-example, filter-branch-ish, etc.)
- Built-in help: `git-filter-repo -h` or `git-filter-repo --help`

## Contribution Standards

Per Contributing.md:
- Target **100% line coverage** for core code (use `make test`)
- Use 2-space indents, follow PEP 8 otherwise
- Bytestrings mandatory (never mix unicode for git data)
- Python 3.6+ features only
- For substantial changes, consider git format-patch + email over GitHub PRs
- Tests must validate expected behavior against test data repos
