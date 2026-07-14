ifndef ROOTDIR
$(error ROOTDIR must be set before including mk/project.mk)
endif

PROJECT_DIR ?= $(CURDIR)
PROJECT_NAME ?= $(notdir $(PROJECT_DIR))
BOARD ?= ulx3s

BOARD_FILE := $(ROOTDIR)/boards/$(BOARD)/board.mk
ifeq ($(wildcard $(BOARD_FILE)),)
$(error Unknown BOARD '$(BOARD)'; expected a directory under boards/)
endif
include $(BOARD_FILE)

BUILD_DIR ?= $(PROJECT_DIR)/build
BSIM_DIR ?= $(PROJECT_DIR)/bsim
HOST_DIR ?= $(PROJECT_DIR)/cpp
TOP_SOURCE ?= $(BOARD_TOP_SOURCE)
TOP_MODULE ?= $(BOARD_TOP_MODULE)
BSIM_TOP_SOURCE ?= $(BOARD_BSIM_TOP_SOURCE)
BSIM_TOP_MODULE ?= $(BOARD_BSIM_TOP_MODULE)
NEEDS_INOUT_FIX ?= 1
POST_RUN ?= :
EXTRA_BSV_PATHS ?=

empty :=
space := $(empty) $(empty)
BSV_DIRS := $(COMMON_BSV_DIRS) $(PLATFORM_BSV_DIRS) $(BOARD_BSV_DIRS) $(PROJECT_DIR) $(EXTRA_BSV_PATHS)
BSV_PATH := $(subst $(space),:,$(strip $(BSV_DIRS)))

BSCFLAGS_COMMON ?= -show-schedule -show-range-conflict -aggressive-conditions
BSCFLAGS_SYNTH := \
	-bdir $(BUILD_DIR) \
	-vdir $(BUILD_DIR) \
	-simdir $(BUILD_DIR) \
	-info-dir $(BUILD_DIR) \
	-fdir $(BUILD_DIR)
BSCFLAGS_BSIM := \
	-bdir $(BSIM_DIR) \
	-vdir $(BSIM_DIR) \
	-simdir $(BSIM_DIR) \
	-info-dir $(BSIM_DIR) \
	-fdir $(BSIM_DIR) \
	-D BSIM \
	-l pthread

BSIM_CPPFILES ?= $(wildcard $(PROJECT_DIR)/cpp/*.cpp) $(wildcard $(ROOTDIR)/lib/cpp/*.cpp)
REPLACETOKEN := $(ROOTDIR)/tools/bin/replacetoken
GENERATED_TOP := $(BUILD_DIR)/$(TOP_MODULE).v

.PHONY: all help print-config check-board check-synth-tools tools hostsoft \
	prepare synth bsim runsim program clean

all: synth

help:
	@printf '%s\n' \
		"Targets: synth bsim runsim program clean print-config" \
		"Variables: BOARD=ulx3s (supported), BOARD=ice40 (scaffold)"

print-config:
	@printf 'PROJECT=%s\nBOARD=%s\nBOARD_STATUS=%s\nTOP=%s:%s\nBSV_PATH=%s\n' \
		'$(PROJECT_NAME)' '$(BOARD)' '$(BOARD_STATUS)' '$(TOP_SOURCE)' '$(TOP_MODULE)' '$(BSV_PATH)'

check-board:
	@if [ "$(BOARD_READY)" != "1" ]; then \
		echo "BOARD=$(BOARD) is not build-ready: $(BOARD_STATUS)" >&2; \
		exit 2; \
	fi

check-synth-tools: check-board
	@command -v bsc >/dev/null || { echo "bsc not found" >&2; exit 127; }
	@command -v apio >/dev/null || { echo "apio not found" >&2; exit 127; }

tools:
	+$(MAKE) -C $(ROOTDIR)/tools

hostsoft:
	@if [ -f "$(HOST_DIR)/Makefile" ]; then \
		$(MAKE) -C "$(HOST_DIR)"; \
	else \
		echo "No host Makefile for $(PROJECT_NAME); skipping host build."; \
	fi

prepare: check-synth-tools tools hostsoft
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)
	cd $(BUILD_DIR) && apio init -b $(APIO_BOARD) -p .

synth: prepare
	bsc $(BSCFLAGS_COMMON) $(BSCFLAGS_SYNTH) -remove-dollar \
		-p +:$(BSV_PATH) -verilog -u -g $(TOP_MODULE) $(TOP_SOURCE)
	cp $(BOARD_CONSTRAINTS) $(BUILD_DIR)/
	@for directory in $(BOARD_RTL_DIRS); do \
		find "$$directory" -maxdepth 1 -type f -name '*.v' -exec cp {} "$(BUILD_DIR)/" \;; \
	done
	@if [ "$(NEEDS_INOUT_FIX)" = "1" ]; then \
		$(ROOTDIR)/scripts/fix_generated_inout.sh "$(GENERATED_TOP)" "$(REPLACETOKEN)"; \
	fi
	cd $(BUILD_DIR) && apio build -v

bsim: check-board
	@command -v bsc >/dev/null || { echo "bsc not found" >&2; exit 127; }
	rm -rf $(BSIM_DIR)
	mkdir -p $(BSIM_DIR)
	bsc $(BSCFLAGS_COMMON) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) \
		-p +:$(BSV_PATH) -sim -u -g $(BSIM_TOP_MODULE) $(BSIM_TOP_SOURCE)
	bsc $(BSCFLAGS_COMMON) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) \
		-sim -e $(BSIM_TOP_MODULE) -o $(BSIM_DIR)/bsim \
		$(BSIM_DIR)/*.ba $(BSIM_CPPFILES)

runsim: bsim
	cd $(PROJECT_DIR) && $(BSIM_DIR)/bsim 2> output.log | tee system.log
	cd $(PROJECT_DIR) && $(POST_RUN)

program: synth
	cd $(BUILD_DIR) && apio upload

clean:
	rm -rf $(BUILD_DIR) $(BSIM_DIR) $(PROJECT_DIR)/cpp/obj
	rm -f $(PROJECT_DIR)/output.log $(PROJECT_DIR)/system.log
