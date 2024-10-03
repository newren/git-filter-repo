#!/bin/bash

test_description='filter-repo tests with reruns'

. ./test-lib.sh

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

DATA="$TEST_DIRECTORY/t9393"
DELETED_SHA="0000000000000000000000000000000000000000" # FIXME: sha256 support

test_expect_success 'a re-run that is treated as a clean slate' '
	test_create_repo clean_slate_rerun &&
	(
		cd clean_slate_rerun &&
		git fast-import --quiet <$DATA/simple &&

		FIRST_ORPHAN=$(git rev-parse orphan-me~1) &&
		FINAL_ORPHAN=$(git rev-parse orphan-me) &&
		FILE_A_CHANGE=$(git rev-list -1 HEAD -- fileA) &&
		FILE_B_CHANGE=$(git rev-list -1 HEAD -- fileB) &&
		FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		ORIGINAL_TAG=$(git rev-parse v1.0) &&

		git filter-repo --invert-paths --path fileB --force &&
		NEW_FILE_C_CHANGE=$(git rev-list -1 HEAD -- fileC) &&
		NEW_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${FILE_B_CHANGE} ${DELETED_SHA}
		${FILE_C_CHANGE} ${NEW_FILE_C_CHANGE}
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${FILE_D_CHANGE} ${NEW_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${ORIGINAL_TAG} ${FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map &&

		touch -t 197001010000 .git/filter-repo/already_ran &&
		echo no | git filter-repo --invert-paths --path fileC --force &&
		FINAL_FILE_D_CHANGE=$(git rev-list -1 HEAD -- fileD) &&
		REALLY_FINAL_TAG=$(git rev-parse v1.0) &&

		cat <<-EOF | sort >sha-expect &&
		${FIRST_ORPHAN} ${FIRST_ORPHAN}
		${FINAL_ORPHAN} ${FINAL_ORPHAN}
		${FILE_A_CHANGE} ${FILE_A_CHANGE}
		${NEW_FILE_C_CHANGE} ${DELETED_SHA}
		${NEW_FILE_D_CHANGE} ${FINAL_FILE_D_CHANGE}
		EOF
		printf "%-40s %s\n" old new >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/commit-map &&

		cat <<-EOF | sort -k 3 >sha-expect &&
		${NEW_FILE_D_CHANGE} ${FINAL_FILE_D_CHANGE} $(git symbolic-ref HEAD)
		${FINAL_ORPHAN} ${FINAL_ORPHAN} refs/heads/orphan-me
		${FINAL_TAG} ${REALLY_FINAL_TAG} refs/tags/v1.0
		EOF
		printf "%-40s %-40s %s\n" old new ref >expect &&
		cat sha-expect >>expect &&
		test_cmp expect .git/filter-repo/ref-map
	)
'

test_done
