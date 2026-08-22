#!/usr/bin/env python3
"""Verify and exhaustively test Unicode 17 Script_Extensions data.

Usage: verify_coverage.py Scripts.txt ScriptExtensions.txt PropertyValueAliases.txt generated_test.zig
"""

import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GENERATOR = Path(__file__).with_name("generate_data.py")
COMMITTED = ROOT / "src/unicode/script_extensions/data.bin"


def main() -> int:
    if len(sys.argv) != 5:
        raise SystemExit(
            "usage: verify_coverage.py Scripts.txt ScriptExtensions.txt "
            "PropertyValueAliases.txt generated_test.zig"
        )
    with tempfile.TemporaryDirectory() as directory:
        generated = Path(directory) / "data.bin"
        subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                sys.argv[1],
                sys.argv[2],
                sys.argv[3],
                str(generated),
                sys.argv[4],
            ],
            check=True,
        )
        if generated.read_bytes() != COMMITTED.read_bytes():
            raise SystemExit("generated Unicode Script_Extensions data.bin is stale")
    print("Unicode 17.0.0 Script_Extensions: 669 explicit scalars in 118 sets")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
