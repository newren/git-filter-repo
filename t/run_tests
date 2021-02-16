#!/bin/bash
set -eu

cd $(dirname $0)

# Put git_filter_repo.py on the front of PYTHONPATH
export PYTHONPATH="$PWD/..${PYTHONPATH:+:$PYTHONPATH}"

# We pretend filenames are unicode for two reasons: (1) because it exercises
# more code, and (2) this setting will detect accidental use of unicode strings
# for file/directory names when it should always be bytestrings.
export PRETEND_UNICODE_ARGS=1

export TEST_SHELL_PATH=/bin/sh

failed=0

for t in t[0-9]*.sh
do
  printf '\n\n== %s ==\n' "$t"
  bash $t "$@" || failed=$(($failed+1))
done

if [ 0 -lt $failed ]
then
  exit 1
fi
