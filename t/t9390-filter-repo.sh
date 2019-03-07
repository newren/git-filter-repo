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

test_done
