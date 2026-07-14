# Compatibility facade

`src/` preserves the paths used by the original `ulx3s_bsv` projects. Its
entries are symbolic links into the new `lib/`, `platforms/`, and `boards/`
layers. New code should use the explicit layers through `mk/project.mk`.
