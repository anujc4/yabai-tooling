SHELL := /bin/bash
SWIFT ?= swift

# CLT-only toolchains hand Testing.framework's directory to the compiler as -I
# rather than -F, so SwiftPM's synthesised test runner cannot import it and
# `swift test` exits 0 having run nothing. Not needed when Xcode is installed.
TESTING_FRAMEWORKS := /Library/Developer/CommandLineTools/Library/Developer/Frameworks
TEST_FLAGS := $(if $(wildcard $(TESTING_FRAMEWORKS)/Testing.framework),-Xswiftc -F -Xswiftc $(TESTING_FRAMEWORKS),)
TEST_LOG := .build/last-test-run.log

PREFIX ?= /usr/local
BINDIR := $(PREFIX)/bin

.PHONY: all build release run test install uninstall formula-sha clean

all: build

build:
	$(SWIFT) build

release:
	$(SWIFT) build -c release

run: build
	$(SWIFT) run yabai-stacks

# Fails loudly when zero tests execute, which is otherwise a silent green.
test:
	@mkdir -p $(dir $(TEST_LOG))
	@set -o pipefail; $(SWIFT) test $(TEST_FLAGS) 2>&1 | tee $(TEST_LOG)
	@summary=$$(grep -E 'Test run with [0-9]+ test' $(TEST_LOG) | tail -1); \
	if [ -z "$$summary" ]; then \
	  echo ""; \
	  echo "FAILED: no test-run summary - zero tests executed."; \
	  echo "        See docs/SPEC.md § Environment."; \
	  exit 1; \
	fi; \
	count=$$(echo "$$summary" | sed -E 's/.*Test run with ([0-9]+) test.*/\1/'); \
	if [ "$$count" -lt 1 ]; then echo "FAILED: zero tests executed."; exit 1; fi; \
	echo "OK: $$count tests executed."

install: release
	@mkdir -p $(BINDIR)
	install -m 755 .build/release/yabai-stacks $(BINDIR)/yabai-stacks
	@echo "installed $(BINDIR)/yabai-stacks"

uninstall:
	rm -f $(BINDIR)/yabai-stacks

# The sha256 the Homebrew formula needs after tagging a release.
formula-sha:
	@test -n "$(VERSION)" || { echo "usage: make formula-sha VERSION=v0.1.0"; exit 1; }
	@curl -sL https://github.com/anujc4/yabai-tooling/archive/refs/tags/$(VERSION).tar.gz | shasum -a 256 | cut -d' ' -f1

clean:
	$(SWIFT) package clean
	rm -rf .build
