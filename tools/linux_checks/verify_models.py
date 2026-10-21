"""Compile portable Linux value-model checks without GTK or Flutter substitutes.

This executes the real data header as C++14. It does not compile the GTK runner,
the GIO launcher or the Flutter adapter; their real-SDK tests live in linux/tests.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


APP_ROOT = Path(__file__).resolve().parents[2]
OUTPUT_ROOT = APP_ROOT / ".dart_tool/linux_architecture_refactor/model_checks"


def compiler_path(value: str | None) -> Path:
    for candidate in (value,) if value else ("g++", "clang++", "c++"):
        if not candidate:
            continue

        resolved = shutil.which(candidate) or candidate
        compiler = Path(resolved).expanduser().resolve()
        if compiler.is_file():
            return compiler

    raise SystemExit("No GCC/Clang C++ compiler found; pass --cxx with its path.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cxx", help="Path to a GCC/Clang C++ compiler.")
    arguments = parser.parse_args()

    compiler = compiler_path(arguments.cxx)
    output = OUTPUT_ROOT.resolve()
    if not output.is_relative_to((APP_ROOT / ".dart_tool").resolve()):
        raise SystemExit("Verification output must stay inside the app's .dart_tool directory.")

    output.mkdir(parents=True, exist_ok=True)
    executable = output / ("directory_open_result_test.exe" if os.name == "nt" else "directory_open_result_test")
    environment = dict(os.environ)
    environment["PATH"] = str(compiler.parent) + os.pathsep + environment.get("PATH", "")

    def run(command: list[str], **kwargs: object) -> subprocess.CompletedProcess:
        return subprocess.run(command, cwd=APP_ROOT, env=environment, check=True, **kwargs)

    target = run([str(compiler), "-dumpmachine"], capture_output=True, text=True).stdout.strip()
    run([
        str(compiler), "-std=c++14", "-Wall", "-Wextra", "-Werror", "-I", str(APP_ROOT / "linux"),
        str(APP_ROOT / "linux/tests/directory_open_result_test.cc"), "-o", str(executable),
    ])
    run([str(executable)])

    result = {
        "directory_outcome_checks": 3,
        "compiler_target": target,
        "gtk_flutter_runner_compiled": False,
        "gio_flutter_contract_tests_run": False,
    }
    (output / "verification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("Portable model verification passed. GTK/GIO/Flutter Linux checks still require a configured Linux build host.")


if __name__ == "__main__":
    main()
