BOARD_READY := 1
BOARD_FAMILY := ecp5
BOARD_STATUS := supported
APIO_BOARD := ulx3s-85f

COMMON_BSV_DIRS := $(ROOTDIR)/lib/bsv
PLATFORM_BSV_DIRS := $(ROOTDIR)/platforms/ecp5/bsv
BOARD_BSV_DIRS := $(ROOTDIR)/boards/ulx3s/bsv
BOARD_RTL_DIRS := \
	$(ROOTDIR)/platforms/bluespec/rtl \
	$(ROOTDIR)/platforms/ecp5/rtl \
	$(ROOTDIR)/boards/ulx3s/rtl
BOARD_CONSTRAINTS := $(ROOTDIR)/boards/ulx3s/constraints/ulx3s.lpf
BOARD_TOP_SOURCE := $(ROOTDIR)/boards/ulx3s/bsv/Top.bsv
BOARD_TOP_MODULE := mkTop
BOARD_BSIM_TOP_SOURCE := $(ROOTDIR)/boards/ulx3s/bsv/Top.bsv
BOARD_BSIM_TOP_MODULE := mkTop_bsim
