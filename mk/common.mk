# mk/common.mk - shared build rules for a single exercise.
#
# An exercise Makefile sets what differs and includes this file:
#
#     NAME := shapes          # binary name          (default: directory name)
#     SRCS := main.asm x.asm  # sources              (default: *.asm, sorted)
#     ARGS := --verbose       # argv for run/test    (default: none)
#     include ../../mk/common.mk
#
# Targets: all (default), run, viz, test, record, disas, clean.
#
# An exercise may also drop a `viz.asm` beside its sources. That file supplies
# its own `main` and is linked against the exercise's classes but NOT against
# its `main.asm`, producing a second binary that draws the object graph the
# exercise builds. Both binaries share every line of the object system and
# differ only in what they print, so the picture cannot describe a layout the
# program does not actually have.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)

NASM      ?= nasm
CC        ?= cc
# Two warnings are silenced on purpose, because both fire on code that is
# correct and central to the experiment:
#   reloc-rel-dword  rip-relative references from .text into .rodata/.data,
#                    i.e. every `lea rdi, [msg]` in a PIE.
#   reloc-abs-qword  absolute 64-bit addresses in .data, i.e. every vtable
#                    entry. The dynamic loader relocates these at startup.
NASMFLAGS ?= -f elf64 -g -F dwarf -w+all -w-orphan-labels \
             -w-reloc-rel-dword -w-reloc-abs-qword \
             -I$(ROOT)/include/
CFLAGS    ?=
LDFLAGS   ?=
LDLIBS    ?=

NAME  ?= $(notdir $(CURDIR))
SRCS  ?= $(filter-out viz.asm,$(sort $(wildcard *.asm)))
BUILD ?= build
OBJS  := $(patsubst %.asm,$(BUILD)/%.o,$(SRCS))
DEPS  := $(patsubst %.asm,$(BUILD)/%.d,$(SRCS))
BIN   := $(BUILD)/$(NAME)

# The drawing half, present only where a viz.asm exists.
VIZ_SRC := $(wildcard viz.asm)
ifneq ($(VIZ_SRC),)
  VIZ_BIN  := $(BUILD)/$(NAME)-viz
  VIZ_OBJS := $(BUILD)/viz.o $(filter-out $(BUILD)/main.o,$(OBJS)) $(BUILD)/libviz.o
endif

.PHONY: all run viz test test-run test-viz record record-run record-viz disas clean
.DELETE_ON_ERROR:

all: $(BIN) $(VIZ_BIN)

$(BUILD):
	@mkdir -p $@

$(BUILD)/%.o: %.asm | $(BUILD)
	$(NASM) $(NASMFLAGS) -MD $(BUILD)/$*.d -o $@ $<

# The canvas is shared by every exercise, so it lives in lib/ and is built into
# this exercise's build directory like any other object.
$(BUILD)/libviz.o: $(ROOT)/lib/viz.asm | $(BUILD)
	$(NASM) $(NASMFLAGS) -MD $(BUILD)/libviz.d -o $@ $<

# Linking through the C driver gives us crt startup, libc and a PIE link for
# free; our assembly simply provides `main`.
$(BIN): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

$(VIZ_BIN): $(VIZ_OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

run: $(BIN)
	@./$(BIN) $(ARGS)

# Golden-output check, used for both binaries: run it, keep the output, diff.
#   $(1) binary   $(2) argv   $(3) artifact stem   $(4) golden file   $(5) label
define golden-check
	@./$(1) $(2) > $(BUILD)/$(3).txt 2>&1; status=$$?; \
	if [ $$status -ne 0 ]; then \
		echo "FAIL  $(NAME)$(5): exited with status $$status"; \
		cat $(BUILD)/$(3).txt; exit 1; \
	fi; \
	if diff -u $(4) $(BUILD)/$(3).txt > $(BUILD)/$(3).diff 2>&1; then \
		echo "  ok    $(NAME)$(5)"; \
	else \
		echo "FAIL  $(NAME)$(5): output does not match $(4)"; \
		cat $(BUILD)/$(3).diff; exit 1; \
	fi
endef

# Exercises must print only deterministic facts, never a raw pointer, so that
# these diffs are stable across runs and machines (ASLR). The diagrams obey the
# same rule: they are drawn from offsets, sizes and identity comparisons, which
# is why a picture of the heap can be a golden file at all.
test: test-run test-viz

test-run: $(BIN)
	$(call golden-check,$(BIN),$(ARGS),actual,expected.txt,)

record: record-run record-viz

record-run: $(BIN)
	@./$(BIN) $(ARGS) > expected.txt && echo "recorded $(NAME)/expected.txt"

ifneq ($(VIZ_SRC),)

viz: $(VIZ_BIN)
	@./$(VIZ_BIN)

test-viz: $(VIZ_BIN)
	$(call golden-check,$(VIZ_BIN),,actual-viz,expected-viz.txt, (viz))

record-viz: $(VIZ_BIN)
	@./$(VIZ_BIN) > expected-viz.txt && echo "recorded $(NAME)/expected-viz.txt"

else

viz:
	@echo "  --    $(NAME): no viz.asm yet"

test-viz record-viz: ;

endif

# Handy when you want to see what the assembler really emitted.
disas: $(BIN)
	@objdump -d -M intel --no-show-raw-insn $(BIN) | sed -n '/>:/,$$p'

clean:
	@rm -rf $(BUILD)

-include $(wildcard $(BUILD)/*.d)
