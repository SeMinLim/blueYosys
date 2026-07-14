# Repository architecture

## Layers

- `projects/`: application and accelerator designs. All seven upstream designs
  are retained in place. Their non-Makefile contents are verified against
  `docs/upstream-project-files.sha256`.
- `lib/`: device-independent Bluespec and host-side libraries.
- `platforms/`: FPGA-family or compiler-runtime implementations. ECP5 and
  Bluespec-generated RTL are separated here; ICE40 has a clean extension point.
- `boards/`: board top levels, peripherals, constraints, and board build
  metadata.
- `mk/`: one shared project build implementation. Project Makefiles only
  declare the exceptional settings.
- `tools/`: reproducibly built source tools; generated executables are not
  committed.
- `src/`: symbolic-link compatibility facade for old paths.

## Dependency direction

`projects -> board/platform/lib`, while board code may depend on platform and
common libraries. Common libraries must not import board-specific packages.
This direction allows a future ICE40 board to reuse the projects without
copying their build systems.

## Migration invariants

1. No `.gitignore` is committed.
2. No upstream project file other than duplicated Makefiles is removed or
   rewritten.
3. ULX3S remains the only build-ready board profile.
4. ICE40 is explicit scaffolding and fails early until a concrete board port is
   complete.
