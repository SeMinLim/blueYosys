# ULX3S board support

This board layer contains only ULX3S-specific clocking, SDRAM pins, top-level
integration, constraints, and RTL wrappers. ECP5 primitives shared with future
ECP5 boards live under `platforms/ecp5/`.

The currently validated build profile is the 85F ULX3S target selected by
`APIO_BOARD=ulx3s-85f`.
