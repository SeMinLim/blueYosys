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

BSC ?= bsc
YOSYS ?= yosys
PROGRAMMER ?= $(BOARD_PROGRAMMER)
PROGRAMMER_FLAGS ?= $(BOARD_PROGRAMMER_FLAGS)

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
BUILD_CONSTRAINTS := $(BUILD_DIR)/$(notdir $(BOARD_CONSTRAINTS))
JSON_NETLIST := $(BUILD_DIR)/$(TOP_MODULE).json
TEXTCFG := $(BUILD_DIR)/$(TOP_MODULE).config
BITSTREAM := $(BUILD_DIR)/$(TOP_MODULE).bit

.PHONY: all help print-config check-board check-bsc check-yosys check-pnr \
	check-pack check-programmer tools host hostsoft prepare verilog netlist pnr \
	bitstream synth bsim runsim program clean

all: synth host

help:
	@printf '%s\n' \
		"Targets: verilog netlist pnr bitstream synth host bsim runsim program clean print-config" \
		"Toolchain: bsc -> yosys -> nextpnr -> packer; APIO is not required" \
		"Variables: BOARD=ulx3s (supported), BOARD=ice40 (scaffold)"

print-config:
	@printf 'PROJECT=%s\nBOARD=%s\nBOARD_STATUS=%s\nTOP=%s:%s\nBSV_PATH=%s\nSYNTH=%s\nPNR=%s\nPACK=%s\nBITSTREAM=%s\n' \
		'$(PROJECT_NAME)' '$(BOARD)' '$(BOARD_STATUS)' '$(TOP_SOURCE)' '$(TOP_MODULE)' '$(BSV_PATH)' \
		'$(YOSYS):$(BOARD_YOSYS_SYNTH)' '$(BOARD_PNR_TOOL)' '$(BOARD_PACK_TOOL)' '$(BITSTREAM)'

check-board:
	@if [ "$(BOARD_READY)" != "1" ]; then \
		echo "BOARD=$(BOARD) is not build-ready: $(BOARD_STATUS)" >&2; \
		exit 2; \
	fi

check-bsc: check-board
	@tool='$(firstword $(BSC))'; command -v "$$tool" >/dev/null || { \
		echo "$$tool not found; install Bluespec Compiler or set BSC=/path/to/bsc" >&2; \
		exit 127; \
	}

check-yosys: check-board
	@tool='$(firstword $(YOSYS))'; command -v "$$tool" >/dev/null || { \
		echo "$$tool not found; install Yosys or set YOSYS=/path/to/yosys" >&2; \
		exit 127; \
	}

check-pnr: check-board
	@tool='$(firstword $(BOARD_PNR_TOOL))'; command -v "$$tool" >/dev/null || { \
		echo "$$tool not found; install the $(BOARD_FAMILY) nextpnr backend or override BOARD_PNR_TOOL" >&2; \
		exit 127; \
	}

check-pack: check-board
	@tool='$(firstword $(BOARD_PACK_TOOL))'; command -v "$$tool" >/dev/null || { \
		echo "$$tool not found; install the $(BOARD_FAMILY) bitstream packer or override BOARD_PACK_TOOL" >&2; \
		exit 127; \
	}

check-programmer: check-board
	@tool='$(firstword $(PROGRAMMER))'; command -v "$$tool" >/dev/null || { \
		echo "$$tool not found; install a programmer or set PROGRAMMER and PROGRAMMER_FLAGS" >&2; \
		exit 127; \
	}

tools:
	+$(MAKE) -C $(ROOTDIR)/tools

host: hostsoft

hostsoft:
	@if [ -f "$(HOST_DIR)/Makefile" ]; then \
		$(MAKE) -C "$(HOST_DIR)"; \
	else \
		echo "No host Makefile for $(PROJECT_NAME); skipping host build."; \
	fi

prepare: check-bsc tools
	rm -rf $(BUILD_DIR)
	mkdir -p $(BUILD_DIR)

verilog: prepare
	$(BSC) $(BSCFLAGS_COMMON) $(BSCFLAGS_SYNTH) -remove-dollar \
		-p +:$(BSV_PATH) -verilog -u -g $(TOP_MODULE) $(TOP_SOURCE)
	cp $(BOARD_CONSTRAINTS) $(BUILD_DIR)/
	@for directory in $(BOARD_RTL_DIRS); do \
		find "$$directory" -maxdepth 1 -type f -name '*.v' -exec cp {} "$(BUILD_DIR)/" \;; \
	done
	@if [ "$(NEEDS_INOUT_FIX)" = "1" ]; then \
		$(ROOTDIR)/scripts/fix_generated_inout.sh "$(GENERATED_TOP)" "$(REPLACETOKEN)"; \
	fi

netlist: verilog check-yosys
	cd $(BUILD_DIR) && $(YOSYS) \
		-p "$(strip $(BOARD_YOSYS_SYNTH) -top $(TOP_MODULE) $(BOARD_YOSYS_FLAGS) -json $(notdir $(JSON_NETLIST)))" \
		*.v

pnr: netlist check-pnr
	$(BOARD_PNR_TOOL) \
		--json $(JSON_NETLIST) \
		--textcfg $(TEXTCFG) \
		--lpf $(BUILD_CONSTRAINTS) \
		$(BOARD_PNR_FLAGS)

bitstream: pnr check-pack
	$(BOARD_PACK_TOOL) $(BOARD_PACK_FLAGS) $(TEXTCFG) $(BITSTREAM)

synth: bitstream
	@printf 'Bitstream: %s\n' '$(BITSTREAM)'

bsim: check-bsc
	rm -rf $(BSIM_DIR)
	mkdir -p $(BSIM_DIR)
	$(BSC) $(BSCFLAGS_COMMON) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) \
		-p +:$(BSV_PATH) -sim -u -g $(BSIM_TOP_MODULE) $(BSIM_TOP_SOURCE)
	$(BSC) $(BSCFLAGS_COMMON) $(BSCFLAGS_BSIM) $(DEBUGFLAGS) \
		-sim -e $(BSIM_TOP_MODULE) -o $(BSIM_DIR)/bsim \
		$(BSIM_DIR)/*.ba $(BSIM_CPPFILES)

runsim: bsim
	cd $(PROJECT_DIR) && $(BSIM_DIR)/bsim 2> output.log | tee system.log
	cd $(PROJECT_DIR) && $(POST_RUN)

program: bitstream check-programmer
	$(PROGRAMMER) $(PROGRAMMER_FLAGS) $(BITSTREAM)

clean:
	rm -rf $(BUILD_DIR) $(BSIM_DIR) $(PROJECT_DIR)/cpp/obj
	rm -f $(PROJECT_DIR)/output.log $(PROJECT_DIR)/system.log
