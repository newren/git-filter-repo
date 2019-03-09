#!/bin/bash

test_description='Basic filter-repo tests'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9390"

filter_testcase() {
	INPUT=$1
	OUTPUT=$2
	shift 2
	REST=("$@")


	NAME="check: $INPUT -> $OUTPUT using '${REST[@]}'"
	test_expect_success "$NAME" '
		# Clean up from previous run
		git pack-refs --all &&
		rm .git/packed-refs &&

		# Run the example
		cat $DATA/$INPUT | git filter-repo --stdin --quiet --force "${REST[@]}" &&

		# Compare the resulting repo to expected value
		git fast-export --use-done-feature --all >compare &&
		test_cmp $DATA/$OUTPUT compare
	'
}

filter_testcase basic basic-filename --path filename
filter_testcase basic basic-twenty   --path twenty
filter_testcase basic basic-ten      --path ten
filter_testcase basic basic-numbers  --path ten --path twenty
filter_testcase basic basic-filename --invert-paths --path-glob 't*en*'
filter_testcase basic basic-numbers  --invert-paths --path-regex 'f.*e.*e'
filter_testcase basic basic-mailmap  --mailmap ../t9390/sample-mailmap
filter_testcase basic basic-replace  --replace-text ../t9390/sample-replace
filter_testcase empty empty-keepme   --path keepme
filter_testcase degenerate degenerate-keepme   --path moduleA/keepme
filter_testcase degenerate degenerate-moduleA  --path moduleA
filter_testcase degenerate degenerate-globme   --path-glob *me

test_expect_success 'setup path_rename' '
	test_create_repo path_rename &&
	(
		cd path_rename &&
		mkdir sequences values &&
		test_seq 1 10 >sequences/tiny &&
		test_seq 100 110 >sequences/intermediate &&
		test_seq 1000 1010 >sequences/large &&
		test_seq 1000 1010 >values/large &&
		test_seq 10000 10010 >values/huge &&
		git add sequences values &&
		git commit -m initial &&

		git mv sequences/tiny sequences/small &&
		cp sequences/intermediate sequences/medium &&
		echo 10011 >values/huge &&
		git add sequences values &&
		git commit -m updates &&

		git rm sequences/intermediate &&
		echo 11 >sequences/small &&
		git add sequences/small &&
		git commit -m changes &&

		echo 1011 >sequences/medium &&
		git add sequences/medium &&
		git commit -m final
	)
'

test_expect_success '--path-rename sequences/tiny:sequences/small' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_single &&
		cd path_rename_single &&
		git filter-repo --path-rename sequences/tiny:sequences/small &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 7 filenames &&
		! grep sequences/tiny filenames &&
		git rev-parse HEAD~3:sequences/small
	)
'

test_expect_success '--path-rename sequences:numbers' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_dir &&
		cd path_rename_dir &&
		git filter-repo --path-rename sequences:numbers &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 8 filenames &&
		! grep sequences/ filenames &&
		grep numbers/ filenames &&
		grep values/ filenames
	)
'

test_expect_success '--path-rename-prefix values:numbers' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_dir_2 &&
		cd path_rename_dir_2 &&
		git filter-repo --path-rename values/:numbers/ &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 8 filenames &&
		! grep values/ filenames &&
		grep sequences/ filenames &&
		grep numbers/ filenames
	)
'

test_expect_success '--path-rename squashing' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_squash &&
		cd path_rename_squash &&
		git filter-repo \
			--path-rename sequences/tiny:sequences/small \
			--path-rename sequences:numbers \
			--path-rename values:numbers \
			--path-rename numbers/intermediate:numbers/medium &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		# Just small, medium, large, huge, and a blank line...
		test_line_count = 5 filenames &&
		! grep sequences/ filenames &&
		! grep values/ filenames &&
		grep numbers/ filenames
	)
'

test_expect_success '--path-rename inability to squash' '
	(
		git clone file://"$(pwd)"/path_rename path_rename_bad_squash &&
		cd path_rename_bad_squash &&
		test_must_fail git filter-repo \
			--path-rename values/large:values/big \
			--path-rename values/huge:values/big 2>../err &&
		test_i18ngrep "File renaming caused colliding pathnames" ../err
	)
'

test_expect_success 'more setup' '
	test_create_repo metasyntactic &&
	(
		cd metasyntactic &&
		weird_name=$(printf "file\tna\nme") &&
		echo "funny" >"$weird_name" &&
		mkdir numbers &&
		test_seq 1 10 >numbers/small &&
		test_seq 100 110 >numbers/medium &&
		git add "$weird_name" numbers &&
		git commit -m initial &&
		git tag v1.0 &&
		git tag -a -m v1.1 v1.1 &&

		mkdir words &&
		echo foo >words/important &&
		echo bar >words/whimsical &&
		echo baz >words/sequences &&
		git add words &&
		git commit -m some.words &&
		git branch another_branch &&
		git tag v2.0 &&

		echo spam >words/to &&
		echo eggs >words/know &&
		git add words
		git rm "$weird_name" &&
		git commit -m more.words &&
		git tag -a -m "Look, ma, I made a tag" v3.0
	)
'

test_expect_success '--tag-rename' '
	(
		git clone file://"$(pwd)"/metasyntactic tag_rename &&
		cd tag_rename &&
		git filter-repo \
			--tag-rename "":"myrepo-" \
			--path words &&
		test_must_fail git cat-file -t v1.0 &&
		test_must_fail git cat-file -t v1.1 &&
		test_must_fail git cat-file -t v2.0 &&
		test_must_fail git cat-file -t v3.0 &&
		test_must_fail git cat-file -t myrepo-v1.0 &&
		test_must_fail git cat-file -t myrepo-v1.1 &&
		test $(git cat-file -t myrepo-v2.0) = commit &&
		test $(git cat-file -t myrepo-v3.0) = tag
	)
'

test_expect_success '--subdirectory-filter' '
	(
		git clone file://"$(pwd)"/metasyntactic subdir_filter &&
		cd subdir_filter &&
		git filter-repo \
			--subdirectory-filter words &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 10 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 6 filenames &&
		grep ^important$ filenames &&
		test_must_fail git cat-file -t v1.0 &&
		test_must_fail git cat-file -t v1.1 &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success '--to-subdirectory-filter' '
	(
		git clone file://"$(pwd)"/metasyntactic to_subdir_filter &&
		cd to_subdir_filter &&
		git filter-repo \
			--to-subdirectory-filter mysubdir &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 22 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		grep "^\"mysubdir/file\\\\tna\\\\nme\"$" filenames &&
		grep ^mysubdir/words/important$ filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'refs/replace/ to skip a parent' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_skip_ref &&
		cd replace_skip_ref &&

		git tag -d v2.0 &&
		git replace HEAD~1 HEAD~2 &&

		git filter-repo --path "" --force &&
		test $(git rev-list --count HEAD) = 2 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 16 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test_must_fail git cat-file -t v2.0 &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_expect_success 'refs/replace/ to add more initial history' '
	(
		git clone file://"$(pwd)"/metasyntactic replace_add_refs &&
		cd replace_add_refs &&

		git checkout --orphan new_root &&
		rm .git/index &&
		git add numbers/small &&
		git clean -fd &&
		git commit -m new.root &&

		git replace --graft master~2 new_root &&
		git checkout master &&

		git --no-replace-objects cat-file -p master~2 >grandparent &&
		! grep parent grandparent &&

		git filter-repo --path "" --force &&

		git --no-replace-objects cat-file -p master~2 >new-grandparent &&
		grep parent new-grandparent &&

		test $(git rev-list --count HEAD) = 4 &&
		git cat-file --batch-check --batch-all-objects >all-objs &&
		test_line_count = 22 all-objs &&
		git log --format=%n --name-only | sort | uniq >filenames &&
		test_line_count = 9 filenames &&
		test $(git cat-file -t v1.0) = commit &&
		test $(git cat-file -t v1.1) = tag &&
		test $(git cat-file -t v2.0) = commit &&
		test $(git cat-file -t v3.0) = tag
	)
'

test_done
