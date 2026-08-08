EMACS ?= emacs
BATCH = $(EMACS) -Q --batch --eval "(package-initialize)" -L . -L test
SOURCES = mode-transient.el mode-transient-use-package.el

.PHONY: all install-deps compile test clean

all: clean compile test

install-deps:
	$(EMACS) -Q --batch --eval "(progn \
	  (require 'package) \
	  (setq package-archives \
	        '((\"gnu-devel\" . \"https://elpa.gnu.org/devel/\") \
	          (\"gnu\" . \"https://elpa.gnu.org/packages/\") \
	          (\"melpa\" . \"https://melpa.org/packages/\"))) \
	  (setq package-archive-priorities \
	        '((\"gnu-devel\" . 10) (\"gnu\" . 5) (\"melpa\" . 3))) \
	  (package-initialize) \
	  (package-refresh-contents) \
	  (unless (package-installed-p 'transient '(0 13 0)) \
	    (package-install (cadr (assq 'transient package-archive-contents)))))"

compile:
	$(BATCH) --eval "(setq byte-compile-error-on-warn t)" \
		-f batch-byte-compile $(SOURCES)

test:
	$(BATCH) -l mode-transient-test \
		-f ert-run-tests-batch-and-exit

clean:
	rm -f *.elc test/*.elc
