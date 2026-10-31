"""Record source identity after Flutter installs its Linux release bundle."""
import argparse
from pathlib import Path
import re
import subprocess

from common import ROOT, run, write_json


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    arguments = parser.parse_args()
    raw = re.search(r"^version:\s*(\S+)", (ROOT / "pubspec.yaml").read_text(), re.M)[1]
    upstream, _, revision = raw.partition("+")
    try:
        commit = run(["git", "rev-parse", "HEAD"], cwd=ROOT)
        dirty = bool(run(["git", "status", "--porcelain"], cwd=ROOT))
    except subprocess.CalledProcessError:
        commit, dirty = None, True
    write_json(arguments.destination, {
        "schema": 1,
        "commit": commit,
        "dirty": dirty,
        "version": upstream,
        "build": revision,
    })


if __name__ == "__main__":
    main()
