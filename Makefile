# Top-level driver. Every directory under exercises/ that has a Makefile is
# part of the ladder; `mk/common.mk` supplies the per-exercise rules.

EXERCISES := $(sort $(patsubst %/Makefile,%,$(wildcard exercises/*/Makefile)))

.PHONY: all test clean list help
.DEFAULT_GOAL := all

help:
	@echo "make            assemble + link every exercise"
	@echo "make test       run every exercise and diff against its expected.txt"
	@echo "make list       show the exercise ladder"
	@echo "make clean      remove build artifacts"
	@echo
	@echo "Per exercise:   make -C exercises/01-objects-are-memory run|test|disas"

all:
	@for d in $(EXERCISES); do $(MAKE) --no-print-directory -C $$d all || exit 1; done

test:
	@fail=0; \
	for d in $(EXERCISES); do \
		$(MAKE) --no-print-directory -C $$d test || fail=1; \
	done; \
	if [ $$fail -ne 0 ]; then echo; echo "some exercises failed"; exit 1; fi; \
	echo; echo "all exercises passed"

clean:
	@for d in $(EXERCISES); do $(MAKE) --no-print-directory -C $$d clean; done

list:
	@for d in $(EXERCISES); do \
		printf '  %-28s %s\n' "$$(basename $$d)" "$$(sed -n 's/^# *//p;1q' $$d/README.md)"; \
	done
