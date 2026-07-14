# Adding a board

1. Create `boards/<board>/board.mk`, `bsv/`, `rtl/`, and `constraints/`.
2. Put device-family primitives in `platforms/<family>/`; do not duplicate them
   per board.
3. Define the variables consumed by `mk/project.mk`: common/platform/board BSV
   directories, RTL directories, constraints, top sources/modules, APIO board,
   and `BOARD_READY`.
4. Keep `BOARD_READY := 0` until synthesis, timing, programming, UART, and any
   external memory interfaces have been tested on hardware.
5. Run `make lint`, then build a small project with
   `make synth PROJECT=test BOARD=<board>`.
