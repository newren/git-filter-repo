#!/bin/bash

test_description='Commit and tag signature tests for filter-repo'

. ./test-lib.sh
. "$TEST_DIRECTORY/lib-gpg.sh"

export PATH=$(dirname $TEST_DIRECTORY):$PATH  # Put git-filter-repo in PATH

if ! test_have_prereq GPGSSH
then
	skip_all='skipping signature tests as ssh signing is not available'
	test_done
fi

compare_revs () {
	local op="$1" &&
	local other="$2" &&
	local rev ours theirs &&

	case "$op" in
	=|!=) ;;
	*) BUG "compare_revs: operator must be '=' or '!=', not '$op'" ;;
	esac &&

	shift 2 &&
	for rev in "$@"
	do
		ours=$(git rev-parse --verify "$rev") &&
		theirs=$(git -C "$other" rev-parse --verify "$rev") ||
		return 1

		if ! test "$ours" "$op" "$theirs"
		then
			echo >&4 "error: compare_revs: '$rev': $ours $op $theirs (in $other) is false"
			return 1
		fi
	done
}

test_lazy_prereq GIT_2_54 '
	git fast-import --signed-tags=strip-if-invalid </dev/null
'

test_expect_success 'setup signed history for signature tests' '
	test_create_repo signed &&
	(
		cd signed &&
		git config gpg.format ssh &&
		git config user.signingkey "${GPGSSH_KEY_PRIMARY}" &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		git config commit.gpgSign true &&

		test_commit initial &&
		git branch side &&
		test_commit second &&
		git checkout side &&
		test_commit third &&
		git checkout - &&
		test_merge merge side &&
		git tag -s -m "signed tag" v1.0 &&

		git verify-commit initial second third merge &&
		git verify-tag v1.0
	)
'

test_expect_success 'signatures are stripped by default' '
	git clone --no-local signed stripped &&
	(
		cd stripped &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&

		git filter-repo --force &&

		compare_revs != ../signed initial second third merge v1.0 &&

		git rev-list --all | git cat-file --batch >commits &&
		! grep -E "^gpgsig(-sha256)? " commits &&
		test_must_fail git verify-commit HEAD &&

		git cat-file tag v1.0 >tag &&
		! grep "BEGIN SSH SIGNATURE" tag &&
		test_must_fail git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 'signatures are preserved with --preserve-signatures' '
	git clone --no-local signed preserved &&
	(
		cd preserved &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&

		git filter-repo --force --preserve-signatures &&

		compare_revs = ../signed initial second third merge v1.0 &&

		git verify-commit initial second third merge &&
		git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 'modified commits and their descendants lose their signatures' '
	git clone --no-local signed modified-commit &&
	(
		cd modified-commit &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		echo "second==>second modified" >../commit-expr &&

		git filter-repo --force --preserve-signatures \
			--replace-message ../commit-expr &&

		compare_revs = ../signed initial third &&
		git verify-commit initial third &&

		compare_revs != ../signed second merge v1.0 &&
		test_must_fail git verify-commit second &&
		test_must_fail git verify-commit merge &&
		test_must_fail git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 'a modified tag loses its signature' '
	git clone --no-local signed modified-tag &&
	(
		cd modified-tag &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		echo "signed tag==>modified tag" >../tag-expr &&

		git filter-repo --force --preserve-signatures \
			--replace-message ../tag-expr &&

		compare_revs = ../signed initial second third merge &&
		git verify-commit initial second third merge &&

		compare_revs != ../signed v1.0 &&
		git cat-file tag v1.0 >tag &&
		grep "modified tag" tag &&
		! grep "BEGIN SSH SIGNATURE" tag &&
		test_must_fail git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 '--preserve-signatures=bogus fails' '
	git clone --no-local signed bogus &&
	(
		cd bogus &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&

		test_must_fail git filter-repo --force --preserve-signatures=bogus 2>err &&
		grep "invalid mode" err &&

		test_must_fail git filter-repo --force --preserve-signatures=re-sign= 2>err &&
		grep "invalid mode" err
	)
'

test_expect_success GIT_2_54 '--preserve-signatures=abort with modified commits' '
	git clone --no-local signed modified-abort &&
	(
		cd modified-abort &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		echo "second==>second modified" >../commit-expr &&

		test_must_fail git filter-repo --force --preserve-signatures=abort \
			--replace-message ../commit-expr 2>err &&

		grep "fast-import failed" err &&
		! grep Traceback err &&

		compare_revs = ../signed initial second third merge v1.0 &&

		git verify-commit initial second third merge &&
		git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 '--preserve-signatures=abort with no modification' '
	git clone --no-local signed preserved-abort &&
	(
		cd preserved-abort &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&

		git filter-repo --force --preserve-signatures=abort &&

		compare_revs = ../signed initial second third merge v1.0 &&

		git verify-commit initial second third merge &&
		git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 '--preserve-signatures=re-sign with modified commits' '
	git clone --no-local signed re-sign-modified &&
	(
		cd re-sign-modified &&
		git config gpg.format ssh &&
		git config user.signingKey "${GPGSSH_KEY_PRIMARY}" &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		echo "second==>second modified" >../commit-expr &&

		git filter-repo --force --preserve-signatures=re-sign \
			--replace-message ../commit-expr &&

		compare_revs = ../signed initial third &&
		compare_revs != ../signed second merge v1.0 &&

		git verify-commit initial second third merge &&
		git verify-tag v1.0
	)
'

test_expect_success GIT_2_54 '--preserve-signatures=re-sign=<keyID> with modified commits' '
	git clone --no-local signed re-sign-keyid &&
	(
		cd re-sign-keyid &&
		git config gpg.format ssh &&
		git config gpg.ssh.allowedSignersFile "${GPGSSH_ALLOWED_SIGNERS}" &&
		echo "second==>second modified" >../commit-expr &&

		git filter-repo --force \
			--preserve-signatures=re-sign="${GPGSSH_KEY_SECONDARY}" \
			--replace-message ../commit-expr &&

		compare_revs = ../signed initial third &&

		git verify-commit initial 2>out &&
		grep "principal with number 1" out &&

		git verify-commit third 2>out &&
		grep "principal with number 1" out &&

		compare_revs != ../signed second merge v1.0 &&

		git verify-commit second 2>out &&
		grep "principal with number 2" out &&

		git verify-commit merge 2>out &&
		grep "principal with number 2" out &&

		git verify-tag v1.0 2>out &&
		grep "principal with number 2" out
	)
'

test_done
