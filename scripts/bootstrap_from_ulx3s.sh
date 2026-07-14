#!/usr/bin/env bash
set -euo pipefail

readonly script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly payload_b64="${script_dir}/.bootstrap_payload.b64"
readonly payload_script="${script_dir}/.bootstrap_payload.sh"
readonly expected_payload_sha256="4fdad25dcdf2c041307703137bd2e9d0ea5d83bf990cbe9110c4d1144339a30a"

cleanup() {
    rm -f "${payload_b64}" "${payload_script}"
}
trap cleanup EXIT

python3 - "${script_dir}/bootstrap.part02.b64" "${script_dir}/bootstrap.part05.b64" <<'PY'
from pathlib import Path
import sys

repairs = (
    (Path(sys.argv[1]), "Qk9SRF9CU0lN", "Qk9BUkRfQlNJ"),
    (Path(sys.argv[2]), "7ZWj7ISx", "7ZWp7ISx"),
)
for path, old, new in repairs:
    text = path.read_text(encoding="ascii")
    count = text.count(old)
    print(f"{path.name}: repairing {count} transport substitution(s)", flush=True)
    if count != 1:
        raise SystemExit(f"unexpected repair count in {path}: {count}")
    path.write_text(text.replace(old, new, 1), encoding="ascii")
PY

cat "${script_dir}"/bootstrap.part*.b64 > "${payload_b64}"
actual_payload_sha256="$(sha256sum "${payload_b64}" | awk '{print $1}')"
printf 'bootstrap payload SHA-256: %s\n' "${actual_payload_sha256}"
if [[ "${actual_payload_sha256}" != "${expected_payload_sha256}" ]]; then
    echo "bootstrap payload checksum mismatch" >&2
    exit 1
fi

base64 --decode "${payload_b64}" > "${payload_script}"
chmod +x "${payload_script}"
bash -n "${payload_script}"
bash "${payload_script}"

# Keep the readable, fully decoded migration script in the resulting repository.
cp "${payload_script}" "${script_dir}/bootstrap_from_ulx3s.sh"
chmod +x "${script_dir}/bootstrap_from_ulx3s.sh"
rm -f "${script_dir}"/bootstrap.part*.b64 "${payload_b64}"
trap - EXIT
rm -f "${payload_script}"
