#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 GENERATED_VERILOG REPLACETOKEN" >&2
    exit 2
fi

readonly verilog_file="$1"
readonly replacetoken="$2"

if [[ ! -f "${verilog_file}" ]]; then
    echo "Generated Verilog not found: ${verilog_file}" >&2
    exit 1
fi
if [[ ! -x "${replacetoken}" ]]; then
    echo "replacetoken is not executable: ${replacetoken}" >&2
    exit 1
fi

temporary_file="$(mktemp "${verilog_file}.XXXXXX")"
trap 'rm -f "${temporary_file}"' EXIT

"${replacetoken}" \
    ".XX_sdram_d_XX(mem_xx_inout16_XX_inout_pins)," "sdram_d," \
    "mem_xx_inout16_XX_inout_pins" "sdram_d" \
    < "${verilog_file}" > "${temporary_file}"

mv "${temporary_file}" "${verilog_file}"
trap - EXIT
