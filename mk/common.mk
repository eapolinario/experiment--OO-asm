# mk/common.mk - shared build rules for a single exercise.
#
# An exercise Makefile sets what differs and includes this file:
#
#     NAME := shapes          # binary name          (default: directory name)
#     SRCS := main.asm x.asm  # sources              (default: *.asm, sorted)
#     ARGS := --verbose       # argv for run/test    (default: none)
#     include ../../mk/common.mk
#
# Targets: all (default), run, test, record, disas, clean.

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))..)

NASM      ?= nasm
CC        ?= cc
# -w-reloc-rel-dword: rip-relative references from .text into .rodata/.data are
# exactly what a PIE wants; NASM 3.x flags them under -w+all anyway.
NASMFLAGS ?= -f elf64 -g -F dwarf -w+all -w-reloc-rel-dword -w-orphan-labels \
             -I$(ROOT)/include/
CFLAGS    ?=
LDFLAGS   ?=
LDLIBS    ?=

NAME  ?= $(notdir $(CURDIR))
SRCS  ?= $(sort $(wildcard *.asm))
BUILD ?= build
OBJS  := $(patsubst %.asm,$(BUILD)/%.o,$(SRCS))
DEPS  := $(patsubst %.asm,$(BUILD)/%.d,$(SRCS))
BIN   := $(BUILD)/$(NAME)

.PHONY: all run test record disas clean
.DELETE_ON_ERROR:

all: $(BIN)

$(BUILD):
	@mkdir -p $@

$(BUILD)/%.o: %.asm | $(BUILD)
	$(NASM) $(NASMFLAGS) -MD $(BUILD)/$*.d -o $@ $<

# Linking through the C driver gives us crt startup, libc and a PIE link for
# free; our assembly simply provides `main`.
$(BIN): $(OBJS)
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $^ $(LDLIBS)

run: $(BIN)
	@./$(BIN) $(ARGS)

# Golden-output test: exercises must print only deterministic facts, never a
# raw pointer, so that this diff is stable across runs and machines (ASLR).
test: $(BIN)
	@./$(BIN) $(ARGS) > $(BUILD)/actual.txt 2>&1; status=$$?; \
	if [ $$status -ne 0 ]; then \
		echo "FAIL $(NAME): exited with status $$status"; \
		cat $(BUILD)/actual.txt; exit 1; \
	fi; \
	if diff -u expected.txt $(BUILD)/actual.txt > $(BUILD)/diff.txt 2>&1; then \
		echo "  ok    $(NAME)"; \
	else \
		echo "FAIL  $(NAME): output does not match expected.txt"; \
		cat $(BUILD)/diff.txt; exit 1; \
	fi

# Regenerate the golden file after an intentional change.
record: $(BIN)
	@./$(BIN) $(ARGS) > expected.txt && echo "recorded $(NAME)/expected.txt"

# Handy when you want to see what the assembler really emitted.
disas: $(BIN)
	@objdump -d -M intel --no-show-raw-insn $(BIN) | sed -n '/>:/,$$p'

clean:
	@rm -rf $(BUILD)

-include $(wildcard $(BUILD)/*.d)
