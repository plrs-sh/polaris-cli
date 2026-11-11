#!/bin/sh
set -eu

release_base="https://github.com/plrs-sh/polaris-cli/releases/latest/download"
install_dir="${POLARIS_INSTALL_DIR:-${HOME}/.local/bin}"

control_free_install_dir="$(printf '%s' "${install_dir}" | LC_ALL=C tr -d '[:cntrl:]')"
if [ "${control_free_install_dir}" != "${install_dir}" ]; then
  echo "Polaris install directory contains unsupported characters." >&2
  exit 2
fi
case "${install_dir}" in
  *'"'*|*'\'*|*"
"*|*""*|*"	"*)
    echo "Polaris install directory contains unsupported characters." >&2
    exit 2
    ;;
esac
case "${install_dir}" in
  /*) ;;
  *) install_dir="./${install_dir}" ;;
esac
mkdir -p "${install_dir}"
install_dir="$(CDPATH= cd -P "${install_dir}" && pwd -P)"

case "$(uname -s)" in
  Linux) target_os="linux" ;;
  Darwin) target_os="darwin" ;;
  *)
    echo "Polaris supports macOS and Linux." >&2
    exit 4
    ;;
esac

case "$(uname -m)" in
  x86_64|amd64) target_arch="amd64" ;;
  arm64|aarch64) target_arch="arm64" ;;
  *)
    echo "Polaris supports x64 and arm64." >&2
    exit 4
    ;;
esac

archive="polaris_${target_os}_${target_arch}.tar.gz"
temporary="$(mktemp -d "${TMPDIR:-/tmp}/polaris-install.XXXXXX")"
temporary="$(CDPATH= cd -P "${temporary}" && pwd -P)"
marker_temporary=""
binary_temporary=""
cleanup() {
  if [ -n "${marker_temporary}" ]; then
    rm -f "${marker_temporary}"
  fi
  if [ -n "${binary_temporary}" ]; then
    rm -f "${binary_temporary}"
  fi
  rm -rf "${temporary}"
}
trap cleanup EXIT HUP INT TERM

curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "${temporary}/${archive}" "${release_base}/${archive}"
curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 \
  --output "${temporary}/checksums.txt" "${release_base}/checksums.txt"

expected="$(awk -v file="${archive}" '$2 == file { print $1 }' "${temporary}/checksums.txt")"
case "${expected}" in
  ''|*[!0-9a-f]*)
    echo "Polaris release checksum is missing or invalid." >&2
    exit 4
    ;;
esac
if [ "${#expected}" -ne 64 ]; then
  echo "Polaris release checksum is missing or invalid." >&2
  exit 4
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "${temporary}/${archive}" | awk '{ print $1 }')"
else
  actual="$(shasum -a 256 "${temporary}/${archive}" | awk '{ print $1 }')"
fi
if [ "${actual}" != "${expected}" ]; then
  echo "Polaris release checksum verification failed." >&2
  exit 4
fi

contents="$(tar -tzf "${temporary}/${archive}")"
if [ "${contents}" != "polaris" ]; then
  echo "Polaris release archive has an invalid layout." >&2
  exit 4
fi
tar -xzf "${temporary}/${archive}" -C "${temporary}" polaris

executable="${install_dir}/polaris"
marker="${executable}.polaris-owner.json"
if [ -e "${executable}" ] && [ ! -f "${marker}" ]; then
  echo "Refusing to replace an existing Polaris binary that is not installer-managed: ${executable}" >&2
  exit 4
fi
if [ -f "${marker}" ]; then
  if ! grep -Fq '"schema_version":1' "${marker}" || \
     ! grep -Fq '"install_method":"installer"' "${marker}" || \
     ! grep -Fq "\"executable\":\"${executable}\"" "${marker}"; then
    echo "Refusing to replace a Polaris binary with an invalid ownership marker: ${executable}" >&2
    exit 4
  fi
fi

marker_temporary="$(mktemp "${install_dir}/.polaris-owner.XXXXXX")"
printf '{"schema_version":1,"install_method":"installer","executable":"%s"}\n' \
  "${executable}" > "${marker_temporary}"
chmod 600 "${marker_temporary}"
sync
mv -f "${marker_temporary}" "${marker}"
marker_temporary=""

binary_temporary="$(mktemp "${install_dir}/.polaris-install.XXXXXX")"
install -m 755 "${temporary}/polaris" "${binary_temporary}"
sync
mv -f "${binary_temporary}" "${executable}"
binary_temporary=""
sync

echo "Installed Polaris at ${executable}"
case ":${PATH}:" in
  *":${install_dir}:"*) ;;
  *) echo "Add ${install_dir} to PATH." ;;
esac
