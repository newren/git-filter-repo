#!/bin/bash

test_description='repo-filter'

. ./test-lib.sh

#set -x

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
		cat $DATA/$INPUT | ../../git-repo-filter --stdin --quiet --force ${REST[@]} &&

		# Compare the resulting repo to expected value
		git fast-export --use-done-feature --all >compare &&
		test_cmp $DATA/$OUTPUT compare
	'
}

filter_testcase case1 case1-filename --path filename
filter_testcase case1 case1-twenty   --path twenty
filter_testcase case1 case1-ten      --path ten

test_done
