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
