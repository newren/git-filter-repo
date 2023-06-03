MAN_BASE_URL := /usr/share/doc/git-doc/
VERSION := $(git log --pretty="%H" -n 1)

ASCIIDOC := asciidoc
ASCIIDOC_EXTRA :=
ASCIIDOC_HTML := xhtml11
ASCIIDOC_DOCBOOK := docbook
ASCIIDOC_CONF := -f asciidoc.conf
ASCIIDOC_COMMON := $(ASCIIDOC) $(ASCIIDOC_EXTRA) $(ASCIIDOC_CONF) \
		-amanversion='$(VERSION)' \
		-amanmanual='git-filter-repo Manual' -amansource='git-filter-repo'
ASCIIDOC_DEPS := asciidoc.conf
TXT_TO_HTML := $(ASCIIDOC_COMMON) -b $(ASCIIDOC_HTML)
TXT_TO_XML := $(ASCIIDOC_COMMON) -b $(ASCIIDOC_DOCBOOK)
MANPAGE_XSL := manpage-normal.xsl
XMLTO := xmlto
XMLTO_EXTRA := -m manpage-bold-literal.xsl -m manpage-base-url.xsl -m manpage-quote-apos.xsl
XMLTO_DEPS := manpage-bold-literal.xsl manpage-base-url.xsl manpage-quote-apos.xsl

manpage-deps := $(XMLTO_DEPS)
manpage-cmd := $(XMLTO) -m $(MANPAGE_XSL) $(XMLTO_EXTRA) man

manpage-base-url.xsl: manpage-base-url.xsl.in
	sed "s|@@MAN_BASE_URL@@|$(MAN_BASE_URL)|" $< > $@

%.xml : %.txt $(ASCIIDOC_DEPS)
	$(QUIET_ASCIIDOC)$(TXT_TO_XML) -d manpage -o $@ $<

man1/%.1 : %.xml $(manpage-deps)
	mkdir -p man1
	$(manpage-cmd) -o man1 $<

html/%.html : %.txt $(ASCIIDOC_DEPS)
	mkdir -p html
	$(TXT_TO_HTML) -d manpage -o $@ $<

man: man1/git-filter-repo.1
html: html/git-filter-repo.html
