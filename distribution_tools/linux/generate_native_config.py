"""Generate public native updater configuration; private keys are never read."""

import argparse
import json
from pathlib import Path

from common import load_json


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("configuration", type=Path)
    parser.add_argument("output", type=Path)
    arguments = parser.parse_args()
    value = json.dumps(load_json(arguments.configuration), separators=(",", ":"))
    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    arguments.output.write_text(
        "#pragma once\nnamespace phonolite { namespace updates {\n"
        f"constexpr char public_configuration[] = {json.dumps(value)};\n"
        "}}\n", encoding="utf-8")


if __name__ == "__main__":
    main()
