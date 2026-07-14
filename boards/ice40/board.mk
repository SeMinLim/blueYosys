BOARD_READY := 0
BOARD_FAMILY := ice40
BOARD_STATUS := scaffold-only: add a concrete board, constraints, clock/reset wrapper, and top module

COMMON_BSV_DIRS := $(ROOTDIR)/lib/bsv
PLATFORM_BSV_DIRS := $(ROOTDIR)/platforms/ice40/bsv
BOARD_BSV_DIRS := $(ROOTDIR)/boards/ice40/bsv
BOARD_RTL_DIRS := $(ROOTDIR)/platforms/bluespec/rtl $(ROOTDIR)/platforms/ice40/rtl $(ROOTDIR)/boards/ice40/rtl
BOARD_CONSTRAINTS :=
BOARD_TOP_SOURCE :=
BOARD_TOP_MODULE :=
BOARD_BSIM_TOP_SOURCE :=
BOARD_BSIM_TOP_MODULE :=
APIO_BOARD :=
