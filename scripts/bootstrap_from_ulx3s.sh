#!/usr/bin/env bash
set -euo pipefail

readonly SOURCE_REPOSITORY="https://github.com/SeMinLim/ulx3s_bsv.git"
readonly SOURCE_REF="master"
readonly ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly WORK_DIR="$(mktemp -d)"
readonly SOURCE_DIR="${WORK_DIR}/ulx3s_bsv"

cleanup() {
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

cd "${ROOT_DIR}"

echo "Cloning ${SOURCE_REPOSITORY} (${SOURCE_REF})..."
git clone --depth 1 --branch "${SOURCE_REF}" "${SOURCE_REPOSITORY}" "${SOURCE_DIR}"
SOURCE_COMMIT="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"

required_projects=(
    image_proc
    matrix4x4
    nn_fc
    nn_fc_accel
    nn_fc_zfpe
    rv32i
    test
)

for project in "${required_projects[@]}"; do
    if [[ ! -d "${SOURCE_DIR}/projects/${project}" ]]; then
        echo "Required project is missing upstream: ${project}" >&2
        exit 1
    fi
done

# Import all project files exactly, including example data and binary assets.
rm -rf projects
cp -a "${SOURCE_DIR}/projects" ./projects

# Record checksums before replacing only the duplicated project Makefiles.
mkdir -p docs
(
    cd "${SOURCE_DIR}"
    find projects -type f ! -name Makefile -print0 \
        | sort -z \
        | xargs -0 sha256sum
) > docs/upstream-project-files.sha256

# Import the legacy source tree, then move implementation files into explicit
# common/platform/board layers. src/ remains as a symlink compatibility facade.
rm -rf src lib platforms boards
cp -a "${SOURCE_DIR}/src" ./src

mkdir -p \
    lib/bsv \
    lib/cpp \
    platforms/bluespec/rtl \
    platforms/ecp5/bsv \
    platforms/ecp5/rtl \
    boards/ulx3s/bsv \
    boards/ulx3s/rtl \
    boards/ulx3s/constraints \
    boards/ice40/bsv \
    boards/ice40/rtl \
    boards/ice40/constraints

mv src/BRAMSubWord.bsv lib/bsv/BRAMSubWord.bsv
mv src/Uart.bsv lib/bsv/Uart.bsv
mv src/cpp/* lib/cpp/
rmdir src/cpp

mv src/Mult18x18D.bsv platforms/ecp5/bsv/Mult18x18D.bsv
mv src/SimpleFloat.bsv platforms/ecp5/bsv/SimpleFloat.bsv
mv src/bsv_verilog/* platforms/bluespec/rtl/
rmdir src/bsv_verilog
mv src/verilog/mult18x18d.v platforms/ecp5/rtl/mult18x18d.v

mv src/PLL.bsv boards/ulx3s/bsv/PLL.bsv
mv src/Sdram.bsv boards/ulx3s/bsv/Sdram.bsv
mv src/Top.bsv boards/ulx3s/bsv/Top.bsv
mv src/verilog/* boards/ulx3s/rtl/
rmdir src/verilog
mv src/ulx3s_bsv.lpf boards/ulx3s/constraints/ulx3s.lpf

# Backward-compatible paths for existing includes and scripts.
ln -s ../lib/bsv/BRAMSubWord.bsv src/BRAMSubWord.bsv
ln -s ../lib/bsv/Uart.bsv src/Uart.bsv
ln -s ../platforms/ecp5/bsv/Mult18x18D.bsv src/Mult18x18D.bsv
ln -s ../platforms/ecp5/bsv/SimpleFloat.bsv src/SimpleFloat.bsv
ln -s ../boards/ulx3s/bsv/PLL.bsv src/PLL.bsv
ln -s ../boards/ulx3s/bsv/Sdram.bsv src/Sdram.bsv
ln -s ../boards/ulx3s/bsv/Top.bsv src/Top.bsv
ln -s ../lib/cpp src/cpp
ln -s ../platforms/bluespec/rtl src/bsv_verilog
ln -s ../boards/ulx3s/rtl src/verilog
ln -s ../boards/ulx3s/constraints/ulx3s.lpf src/ulx3s_bsv.lpf

# Import tools as source only. The tracked host-specific ELF is intentionally
# replaced by a deterministic local build.
rm -rf tools
cp -a "${SOURCE_DIR}/tools" ./tools
rm -rf tools/bin

cat > tools/Makefile <<'MAKE'
CC ?= cc
CFLAGS ?= -O2 -std=c11 -Wall -Wextra -Wpedantic
CPPFLAGS ?= -D_POSIX_C_SOURCE=200809L

BIN_DIR := bin
TARGET := $(BIN_DIR)/replacetoken

.PHONY: all clean

all: $(TARGET)

$(TARGET): replacetoken.c | $(BIN_DIR)
	$(CC) $(CPPFLAGS) $(CFLAGS) -o $@ $<

$(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf $(BIN_DIR)
MAKE

cat > tools/replacetoken.c <<'C'
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void usage(const char *program)
{
    fprintf(stderr,
            "Usage: %s FROM TO [FROM TO ...]\n"
            "Reads stdin, replaces every occurrence, and writes stdout.\n",
            program);
}

static char *replace_all(const char *input, const char *from, const char *to)
{
    const size_t input_len = strlen(input);
    const size_t from_len = strlen(from);
    const size_t to_len = strlen(to);
    size_t count = 0;
    const char *cursor = input;
    const char *match = NULL;

    if (from_len == 0U) {
        errno = EINVAL;
        return NULL;
    }

    while ((match = strstr(cursor, from)) != NULL) {
        ++count;
        cursor = match + from_len;
    }

    if (count == 0U) {
        return strdup(input);
    }

    size_t output_len = input_len;
    if (to_len >= from_len) {
        const size_t growth = to_len - from_len;
        if (growth != 0U && count > (SIZE_MAX - output_len - 1U) / growth) {
            errno = EOVERFLOW;
            return NULL;
        }
        output_len += count * growth;
    } else {
        output_len -= count * (from_len - to_len);
    }

    char *output = malloc(output_len + 1U);
    if (output == NULL) {
        return NULL;
    }

    const char *read_ptr = input;
    char *write_ptr = output;
    while ((match = strstr(read_ptr, from)) != NULL) {
        const size_t prefix_len = (size_t)(match - read_ptr);
        memcpy(write_ptr, read_ptr, prefix_len);
        write_ptr += prefix_len;
        memcpy(write_ptr, to, to_len);
        write_ptr += to_len;
        read_ptr = match + from_len;
    }

    const size_t tail_len = strlen(read_ptr);
    memcpy(write_ptr, read_ptr, tail_len + 1U);
    return output;
}

int main(int argc, char **argv)
{
    if (argc < 3 || ((argc - 1) % 2) != 0) {
        usage(argv[0]);
        return EXIT_FAILURE;
    }

    for (int index = 1; index < argc; index += 2) {
        if (argv[index][0] == '\0') {
            fprintf(stderr, "FROM token must not be empty.\n");
            return EXIT_FAILURE;
        }
    }

    char *line = NULL;
    size_t capacity = 0U;
    ssize_t length = 0;

    while ((length = getline(&line, &capacity, stdin)) >= 0) {
        (void)length;
        char *current = strdup(line);
        if (current == NULL) {
            perror("strdup");
            free(line);
            return EXIT_FAILURE;
        }

        for (int index = 1; index < argc; index += 2) {
            char *next = replace_all(current, argv[index], argv[index + 1]);
            free(current);
            if (next == NULL) {
                perror("replace_all");
                free(line);
                return EXIT_FAILURE;
            }
            current = next;
        }

        if (fputs(current, stdout) == EOF) {
            perror("stdout");
            free(current);
            free(line);
            return EXIT_FAILURE;
        }
        free(current);
    }

    if (ferror(stdin) != 0) {
        perror("stdin");
        free(line);
        return EXIT_FAILURE;
    }

    free(line);
    return EXIT_SUCCESS;
}
C

mkdir -p mk scripts

cat > boards/ulx3s/board.mk <<'MAKE'
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
MAKE

cat > boards/ulx3s/README.md <<'MD'
# ULX3S board support

This board layer contains only ULX3S-specific clocking, SDRAM pins, top-level
integration, constraints, and RTL wrappers. ECP5 primitives shared with future
ECP5 boards live under `platforms/ecp5/`.

The currently validated build profile is the 85F ULX3S target selected by
`APIO_BOARD=ulx3s-85f`.
MD

cat > boards/ice40/board.mk <<'MAKE'
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
MAKE

mkdir -p platforms/ice40/bsv platforms/ice40/rtl
cat > boards/ice40/README.md <<'MD'
# ICE40 support plan

ICE40 is intentionally represented as a non-buildable scaffold rather than a
false claim of support. To enable a concrete ICE40 board:

1. Add board constraints and a clock/reset/top wrapper under this directory.
2. Add ICE40 primitive wrappers under `platforms/ice40/`.
3. Provide a multiplier backend for designs that currently use ECP5
   `MULT18X18D` through `SimpleFloat`.
4. Set `BOARD_READY := 1`, select the exact APIO board, and add hardware CI.

The common Bluespec libraries and every design under `projects/` are already
kept independent of the ULX3S build dispatch, so this can be added without
reorganizing the applications again.
MD

cat > platforms/ice40/README.md <<'MD'
# ICE40 platform layer

Place device-family primitive wrappers here. Board pin constraints and board
clocking policy belong under `boards/<board>/`, not in this directory.
MD

cat > src/README.md <<'MD'
# Compatibility facade

`src/` preserves the paths used by the original `ulx3s_bsv` projects. Its
entries are symbolic links into the new `lib/`, `platforms/`, and `boards/`
layers. New code should use the explicit layers through `mk/project.mk`.
MD

cat > scripts/fix_generated_inout.sh <<'BASH2'
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
BASH2
chmod +x scripts/fix_generated_inout.sh

cat > mk/project.mk <<'MAKE'
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
MAKE

cat > projects/image_proc/Makefile <<'MAKE'
ROOTDIR := $(abspath ../..)
PROJECT_NAME := image_proc
POST_RUN := python3 output2png.py
include $(ROOTDIR)/mk/project.mk
MAKE

for project in matrix4x4 nn_fc nn_fc_accel nn_fc_zfpe test; do
    cat > "projects/${project}/Makefile" <<MAKE
ROOTDIR := \$(abspath ../..)
PROJECT_NAME := ${project}
include \$(ROOTDIR)/mk/project.mk
MAKE
done

cat > projects/rv32i/Makefile <<'MAKE'
ROOTDIR := $(abspath ../..)
PROJECT_NAME := rv32i
TOP_SOURCE := $(CURDIR)/Top.bsv
TOP_MODULE := mkTop
BSIM_TOP_SOURCE := $(CURDIR)/Top.bsv
BSIM_TOP_MODULE := mkTop_bsim
EXTRA_BSV_PATHS := $(CURDIR)/processor
NEEDS_INOUT_FIX := 0
include $(ROOTDIR)/mk/project.mk
MAKE

cat > Makefile <<'MAKE'
PROJECTS := image_proc matrix4x4 nn_fc nn_fc_accel nn_fc_zfpe rv32i test
PROJECT ?= test
BOARD ?= ulx3s

.PHONY: help list-projects tools lint synth bsim runsim program clean clean-all

help:
	@printf '%s\n' \
		"blueYosys build dispatcher" \
		"  make synth PROJECT=test BOARD=ulx3s" \
		"  make bsim PROJECT=matrix4x4" \
		"  make lint" \
		"  make list-projects"

list-projects:
	@printf '%s\n' $(PROJECTS)

tools:
	+$(MAKE) -C tools

lint:
	bash scripts/lint_repo.sh

synth bsim runsim program clean:
	@test -d "projects/$(PROJECT)" || { \
		echo "Unknown PROJECT=$(PROJECT). Run 'make list-projects'." >&2; \
		exit 2; \
	}
	+$(MAKE) -C "projects/$(PROJECT)" BOARD="$(BOARD)" $@

clean-all:
	@for project in $(PROJECTS); do \
		$(MAKE) -C "projects/$$project" clean; \
	done
	+$(MAKE) -C tools clean
MAKE

cat > scripts/lint_repo.sh <<'BASH2'
#!/usr/bin/env bash
set -euo pipefail

readonly root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${root_dir}"

projects=(image_proc matrix4x4 nn_fc nn_fc_accel nn_fc_zfpe rv32i test)

if find . -name .gitignore -print -quit | grep -q .; then
    echo ".gitignore must not exist in blueYosys." >&2
    exit 1
fi

for project in "${projects[@]}"; do
    test -d "projects/${project}" || {
        echo "Missing project: ${project}" >&2
        exit 1
    }
    test -f "projects/${project}/Makefile" || {
        echo "Missing project Makefile: ${project}" >&2
        exit 1
    }
done

sha256sum --check --quiet docs/upstream-project-files.sha256

while IFS= read -r -d '' script; do
    bash -n "${script}"
done < <(find scripts projects -type f -name '*.sh' -print0)

while IFS= read -r -d '' python_file; do
    python3 -m py_compile "${python_file}"
done < <(find projects -type f -name '*.py' -print0)
find projects -type d -name __pycache__ -prune -exec rm -rf {} +

make -C tools clean all

actual="$(printf 'abc abc\n' | tools/bin/replacetoken abc x)"
[[ "${actual}" == "x x" ]] || {
    echo "replacetoken failed shorter/repeated replacement test." >&2
    exit 1
}
actual="$(printf 'a-z-a\n' | tools/bin/replacetoken a alphabet z Z)"
[[ "${actual}" == "alphabet-Z-alphabet" ]] || {
    echo "replacetoken failed longer/multiple-pair test." >&2
    exit 1
}
if tools/bin/replacetoken only-one-token </dev/null >/dev/null 2>&1; then
    echo "replacetoken accepted an invalid argument list." >&2
    exit 1
fi
make -C tools clean

for project in "${projects[@]}"; do
    make --no-print-directory -C "projects/${project}" -n print-config BOARD=ulx3s >/dev/null
done
make --no-print-directory -C projects/test -n print-config BOARD=ice40 >/dev/null

test -L src/Top.bsv
test -L src/cpp
test -f boards/ulx3s/constraints/ulx3s.lpf

echo "Repository lint passed."
BASH2
chmod +x scripts/lint_repo.sh

cat > docs/architecture.md <<'MD'
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
MD

cat > docs/adding-a-board.md <<'MD'
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
MD

cat > README.md <<'README'
# blueYosys

Bluespec 기반 하드웨어 가속기를 오픈소스 Yosys 계열 도구로 빌드하기 위한
멀티보드 저장소입니다. 현재 **Lattice ECP5 / ULX3S-85F**를 지원하며,
**ICE40**은 향후 포팅을 위한 명시적인 스캐폴드만 제공합니다.

## 핵심 변경

- 원본 `ulx3s_bsv`의 7개 `projects/` 설계를 데이터 파일까지 모두 유지합니다.
- 공통 라이브러리, FPGA 패밀리, 보드 계층을 `lib/`, `platforms/`,
  `boards/`로 분리했습니다.
- 중복된 프로젝트 Makefile을 `mk/project.mk` 하나로 통합했습니다.
- 잘못된 Makefile recipe와 누락된 `nn_fc_zfpe/Makefile`을 수정했습니다.
- `replacetoken`의 짧은 문자열 치환 시 정수 언더플로, 첫 항목만 치환하는
  문제, 잘못된 인자 처리, 메모리 해제 누락을 수정했습니다.
- 생성 바이너리는 커밋하지 않고 `make tools`로 재현합니다.
- 요청에 따라 `.gitignore`은 저장소에 두지 않습니다.

Upstream snapshot: `SeMinLim/ulx3s_bsv@SOURCE_COMMIT_PLACEHOLDER`

## 사용법

```sh
make list-projects
make lint
make synth PROJECT=test BOARD=ulx3s
make bsim PROJECT=matrix4x4 BOARD=ulx3s
make program PROJECT=test BOARD=ulx3s
```

필수 합성 도구는 Bluespec Compiler(`bsc`), APIO, Yosys/nextpnr-ecp5
툴체인입니다. 호스트 유틸리티 빌드에는 C/C++ 컴파일러가 필요합니다.

## 구조

```text
boards/       보드별 top, 주변장치, constraint, build metadata
lib/          디바이스 독립 Bluespec/C++ 라이브러리
platforms/    ECP5/ICE40 및 Bluespec runtime 계층
projects/     보존된 가속기/프로세서 설계 7종
mk/           공통 빌드 로직
scripts/      생성 Verilog 수정 및 저장소 검증
tools/        소스에서 재현되는 보조 도구
src/          기존 경로 호환용 symbolic-link facade
```

세부 설계 원칙은 `docs/architecture.md`, 새 보드 추가 절차는
`docs/adding-a-board.md`를 참고하십시오.
README
sed -i "s/SOURCE_COMMIT_PLACEHOLDER/${SOURCE_COMMIT}/" README.md

cat > docs/upstream-source.txt <<EOF
Repository: ${SOURCE_REPOSITORY}
Ref: ${SOURCE_REF}
Commit: ${SOURCE_COMMIT}
Imported by: scripts/bootstrap_from_ulx3s.sh
EOF

# Remove all ignore files exactly as requested, including the imported root one.
find . -name .gitignore -type f -delete


echo "Imported ${SOURCE_COMMIT} and generated blueYosys hierarchy."
