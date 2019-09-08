#!/bin/bash

die() { echo "$@"; exit 1; }
orig_doc_dir="$(cd $(dirname $0) && pwd -P)"
git_clone_path="$orig_doc_dir"/../git
test -d "$git_clone_path" || die "Couldn't find git"
cd $git_clone_path/Documentation
ln -sf "$orig_doc_dir"/git-filter-repo.txt .
make -j4 man html
rm -rf ${orig_doc_dir}/{man1,html}
mkdir ${orig_doc_dir}/{man1,html}
cp -a git-filter-repo.1 ${orig_doc_dir}/man1/
cp -a *.html ${orig_doc_dir}/html/
dos2unix ${orig_doc_dir}/html/*
