# Run tests
#
# Copyright (c) 2005 Junio C Hamano
# Modified 2009 by Elijah Newren to get minimal version needed for
# git_fast_filter.py
#

#GIT_TEST_OPTS=--verbose --debug
SHELL_PATH ?= $(SHELL)
TAR ?= $(TAR)
RM ?= rm -f

# Shell quote;
SHELL_PATH_SQ = $(subst ','\'',$(SHELL_PATH))

T = $(wildcard t[0-9][0-9][0-9][0-9]-*.sh)

all: pre-clean
	$(MAKE) aggregate-results-and-cleanup

$(T):
	@echo "*** $@ ***"; GIT_CONFIG=.git/config '$(SHELL_PATH_SQ)' $@ $(GIT_TEST_OPTS)

pre-clean:
	$(RM) -r test-results

clean:
	$(RM) -r 'trash directory'.* test-results

aggregate-results-and-cleanup: $(T)
	$(MAKE) clean

.PHONY: pre-clean $(T) clean
