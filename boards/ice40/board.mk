BOARD_READY := 0
BOARD_FAMILY := ice40
BOARD_STATUS := scaffold-only: add a concrete board, constraints, clock/reset wrapper, top module, and direct tool settings

# Populate these when a concrete ICE40 board is selected.
BOARD_YOSYS_SYNTH := synth_ice40
BOARD_YOSYS_FLAGS :=
BOARD_PNR_TOOL :=
BOARD_PNR_FLAGS :=
BOARD_PACK_TOOL :=
BOARD_PACK_FLAGS :=
BOARD_PROGRAMMER :=
BOARD_PROGRAMMER_FLAGS :=

COMMON_BSV_DIRS := $(ROOTDIR)/lib/bsv
PLATFORM_BSV_DIRS := $(ROOTDIR)/platforms/ice40/bsv
BOARD_BSV_DIRS := $(ROOTDIR)/boards/ice40/bsv
BOARD_RTL_DIRS := $(ROOTDIR)/platforms/bluespec/rtl $(ROOTDIR)/platforms/ice40/rtl $(ROOTDIR)/boards/ice40/rtl
BOARD_CONSTRAINTS :=
BOARD_TOP_SOURCE :=
BOARD_TOP_MODULE :=
BOARD_BSIM_TOP_SOURCE :=
BOARD_BSIM_TOP_MODULE :=
