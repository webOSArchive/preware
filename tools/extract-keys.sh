#!/bin/bash
# Extract the app signing keys (cert.pem, pubkey.pem, signature.sha1) from an
# official, previously-signed .ipk and copy them into keys/, where build.sh
# expects to find them.
#
# Usage: tools/extract-keys.sh /path/to/org.webosinternals.preware_X.Y.Z_arm.ipk
#
# macOS's built-in `ar` can't extract members from GNU-style ar archives
# (the format ipkg-build/dpkg-deb produce, with a "//" long-filename table),
# which is what most official Preware ipks are. So this parses the ar
# archive directly instead of shelling out to `ar`.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 /path/to/signed.ipk" >&2
    exit 1
fi

IPK="$1"
if [ ! -f "$IPK" ]; then
    echo "error: $IPK not found" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KEYS_DIR="$SCRIPT_DIR/../keys"
mkdir -p "$KEYS_DIR"

python3 - "$IPK" "$KEYS_DIR" <<'PYEOF'
import sys

ipk_path, keys_dir = sys.argv[1], sys.argv[2]
wanted = ["cert.pem", "pubkey.pem", "signature.sha1"]

with open(ipk_path, "rb") as f:
    data = f.read()

if data[:8] != b"!<arch>\n":
    sys.exit(f"error: {ipk_path} is not an ar archive (not an ipk?)")

long_names = {}  # offset -> name, from the GNU "//" long-filename table
found = {}
i = 8
while i + 60 <= len(data):
    header = data[i:i + 60]
    if header[58:60] != b"`\n":
        break  # not a valid ar header, stop
    raw_name = header[0:16].decode("latin1").rstrip()
    size = int(header[48:58].decode("latin1").strip())
    body_start = i + 60
    body = data[body_start:body_start + size]

    if raw_name == "//":
        # GNU long-filename table: entries are "name/\n", indexed by byte offset
        offset = 0
        text = body.decode("latin1")
        for entry in text.split("\n"):
            if entry == "":
                continue
            long_names[str(offset)] = entry.rstrip("/")
            offset += len(entry) + 1
    elif raw_name.startswith("/") and raw_name[1:].isdigit():
        # GNU long name reference into the "//" table
        name = long_names.get(raw_name[1:], raw_name)
        if name in wanted and name not in found:
            found[name] = body
    elif raw_name.startswith("#1/") and raw_name[3:].isdigit():
        # BSD extended name: name is the first N bytes of the body
        n = int(raw_name[3:])
        name = body[:n].decode("latin1").rstrip("\x00")
        content = body[n:]
        if name in wanted and name not in found:
            found[name] = content
    else:
        name = raw_name.rstrip("/")
        if name in wanted and name not in found:
            found[name] = body

    i = body_start + size
    if size % 2 == 1:
        i += 1  # ar pads members to even length

missing = [name for name in wanted if name not in found]
if missing:
    sys.exit(
        f"error: {ipk_path} does not contain signing keys ({', '.join(missing)} missing).\n"
        "       This is not an officially signed release ipk."
    )

for name, content in found.items():
    out_path = f"{keys_dir}/{name}"
    with open(out_path, "wb") as out:
        out.write(content)
    print(f"wrote {out_path} ({len(content)} bytes)")
PYEOF

echo
echo "keys extracted to $KEYS_DIR"
