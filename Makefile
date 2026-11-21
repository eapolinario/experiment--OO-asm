# Top-level driver. Every directory under exercises/ that has a Makefile is
# part of the ladder; `mk/common.mk` supplies the per-exercise rules.

EXERCISES := $(sort $(patsubst %/Makefile,%,$(wildcard exercises/*/Makefile)))

NASM      ?= nasm
CC        ?= cc
NASMFLAGS ?= -f elf64 -g -F dwarf -I$(CURDIR)/include/
VIZ_TEST_BIN := build/viz-test

.PHONY: all test test-viz-api viz clean list help
.DEFAULT_GOAL := all

help:
	@echo "make            assemble + link every exercise"
	@echo "make test       run exercise and canvas golden tests"
	@echo "make viz        draw the memory maps, where an exercise has them"
	@echo "make list       show the exercise ladder"
	@echo "make clean      remove build artifacts"
	@echo
	@echo "Per exercise:   make -C exercises/01-objects-are-memory run|viz|test|disas"

all:
	@for d in $(EXERCISES); do $(MAKE) --no-print-directory -C $$d all || exit 1; done

test:
	@fail=0; \
	for d in $(EXERCISES); do \
		$(MAKE) --no-print-directory -C $$d test || fail=1; \
	done; \
	$(MAKE) --no-print-directory test-viz-api || fail=1; \
	if [ $$fail -ne 0 ]; then echo; echo "some exercises failed"; exit 1; fi; \
	echo; echo "all exercises passed"

build:
	@mkdir -p $@

build/viz-test.o: lib/viz_test.asm include/abi.inc include/libc.inc include/viz.inc | build
	$(NASM) $(NASMFLAGS) -MD build/viz-test.d -o $@ $<

build/libviz.o: lib/viz.asm include/abi.inc include/libc.inc include/viz.inc | build
	$(NASM) $(NASMFLAGS) -MD build/libviz.d -o $@ $<

$(VIZ_TEST_BIN): build/viz-test.o build/libviz.o
	$(CC) -o $@ $^

test-viz-api: $(VIZ_TEST_BIN)
	@./$(VIZ_TEST_BIN) > build/viz-test.actual.txt 2>&1; status=$$?; \
	if [ $$status -ne 0 ]; then \
		echo "FAIL  viz-api: exited with status $$status"; \
		cat build/viz-test.actual.txt; exit 1; \
	fi; \
	if diff -u lib/expected-viz-test.txt build/viz-test.actual.txt > build/viz-test.diff 2>&1; then \
		echo "  ok    viz-api"; \
	else \
		echo "FAIL  viz-api: output does not match lib/expected-viz-test.txt"; \
		cat build/viz-test.diff; exit 1; \
	fi

-include build/viz-test.d build/libviz.d

# Every exercise that ships a viz.asm draws itself. The ones that do not say
# so, which doubles as the to-do list.
viz:
	@for d in $(EXERCISES); do $(MAKE) --no-print-directory -C $$d viz || exit 1; done

clean:
	@for d in $(EXERCISES); do $(MAKE) --no-print-directory -C $$d clean; done

list:
	@for d in $(EXERCISES); do \
		printf '  %-28s %s\n' "$$(basename $$d)" "$$(sed -n 's/^# *//p;1q' $$d/README.md)"; \
	done
