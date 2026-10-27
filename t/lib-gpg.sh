# This is a trimmed copy of git.git's t/lib-gpg.sh (as of 8f0d663eac,
# git v2.56.0), under GPL2 (see COPYING.gpl)

# We always set GNUPGHOME, even if no usable GPG was found, as
#
# - It does not hurt, and
#
# - we cannot set global environment variables in lazy prereqs because they are
#   executed in an eval'ed subshell that changes the working directory to a
#   temporary one.

GNUPGHOME="$(pwd)/gpghome"
export GNUPGHOME

# All the "test_lazy_prereq GPG*" below should use
# `prepare_gnupghome()` either directly or through a call to
# `test_have_prereq GPG*`. That's because `gpg` and `gpgsm`
# only create the directory specified using "$GNUPGHOME" or
# `--homedir` if it's the default (usually "~/.gnupg").
prepare_gnupghome() {
	mkdir -p "$GNUPGHOME" &&
	chmod 0700 "$GNUPGHOME"
}

GPGSSH_KEY_PRIMARY="${GNUPGHOME}/ed25519_ssh_signing_key"
GPGSSH_KEY_SECONDARY="${GNUPGHOME}/rsa_2048_ssh_signing_key"
GPGSSH_KEY_UNTRUSTED="${GNUPGHOME}/untrusted_ssh_signing_key"
GPGSSH_KEY_EXPIRED="${GNUPGHOME}/expired_ssh_signing_key"
GPGSSH_KEY_NOTYETVALID="${GNUPGHOME}/notyetvalid_ssh_signing_key"
GPGSSH_KEY_TIMEBOXEDVALID="${GNUPGHOME}/timeboxed_valid_ssh_signing_key"
GPGSSH_KEY_TIMEBOXEDINVALID="${GNUPGHOME}/timeboxed_invalid_ssh_signing_key"
GPGSSH_KEY_WITH_PASSPHRASE="${GNUPGHOME}/protected_ssh_signing_key"
GPGSSH_KEY_ECDSA="${GNUPGHOME}/ecdsa_ssh_signing_key"
GPGSSH_KEY_PASSPHRASE="super_secret"
GPGSSH_ALLOWED_SIGNERS="${GNUPGHOME}/ssh.all_valid.allowedSignersFile"

GPGSSH_GOOD_SIGNATURE_TRUSTED='Good "git" signature for'
GPGSSH_GOOD_SIGNATURE_UNTRUSTED='Good "git" signature with'
GPGSSH_KEY_NOT_TRUSTED="No principal matched"
GPGSSH_BAD_SIGNATURE="Signature verification failed"

test_lazy_prereq GPGSSH '
	ssh_version=$(ssh-keygen -Y find-principals -n "git" 2>&1)
	test $? != 127 || exit 1
	echo $ssh_version | grep -q "find-principals:missing signature file"
	test $? = 0 || exit 1;

	# Setup some keys and an allowed signers file
	prepare_gnupghome &&
	(setfacl -k "${GNUPGHOME}" 2>/dev/null || true) &&
	ssh-keygen -t ed25519 -N "" -C "git ed25519 key" -f "${GPGSSH_KEY_PRIMARY}" >/dev/null &&
	ssh-keygen -t rsa -b 2048 -N "" -C "git rsa2048 key" -f "${GPGSSH_KEY_SECONDARY}" >/dev/null &&
	ssh-keygen -t ed25519 -N "${GPGSSH_KEY_PASSPHRASE}" -C "git ed25519 encrypted key" -f "${GPGSSH_KEY_WITH_PASSPHRASE}" >/dev/null &&
	ssh-keygen -t ecdsa -N "" -f "${GPGSSH_KEY_ECDSA}" >/dev/null &&
	ssh-keygen -t ed25519 -N "" -C "git ed25519 key" -f "${GPGSSH_KEY_UNTRUSTED}" >/dev/null &&

	cat >"${GPGSSH_ALLOWED_SIGNERS}" <<-EOF &&
	"principal with number 1" $(cat "${GPGSSH_KEY_PRIMARY}.pub")"
	"principal with number 2" $(cat "${GPGSSH_KEY_SECONDARY}.pub")"
	"principal with number 3" $(cat "${GPGSSH_KEY_WITH_PASSPHRASE}.pub")"
	"principal with number 4" $(cat "${GPGSSH_KEY_ECDSA}.pub")"
	EOF

	# Verify if at least one key and ssh-keygen works as expected
	echo "testpayload" |
	ssh-keygen -Y sign -n "git" -f "${GPGSSH_KEY_PRIMARY}" >gpgssh_prereq.sig &&
	ssh-keygen -Y find-principals -f "${GPGSSH_ALLOWED_SIGNERS}" -s gpgssh_prereq.sig &&
	echo "testpayload" |
	ssh-keygen -Y verify -n "git" -f "${GPGSSH_ALLOWED_SIGNERS}" -I "principal with number 1" -s gpgssh_prereq.sig
'
