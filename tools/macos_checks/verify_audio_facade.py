"""Compile the portable audio facade contract checks without Apple SDK substitutes.

This checks the real C facade against typed doubles of its internal contracts.
It does not compile AudioQueue/CoreAudio, build Runner or exercise audio hardware.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess


APP_ROOT = Path(__file__).resolve().parents[2]
NATIVE_ROOT = APP_ROOT / "macos/Runner/Infrastructure/Audio/Native"
TEST_ROOT = APP_ROOT / "macos/NativeTests"
OUTPUT_ROOT = APP_ROOT / ".dart_tool/macos_architecture_refactor/native_checks"


def compiler_path(value: str | None, candidates: tuple[str, ...]) -> Path:
    if value:
        resolved = shutil.which(value) or value
        compiler = Path(resolved).expanduser().resolve()
        if compiler.is_file():
            return compiler

        raise SystemExit(f"Compiler not found: {value}")

    for candidate in candidates:
        resolved = shutil.which(candidate)
        if resolved:
            return Path(resolved).resolve()

    raise SystemExit("No GCC/Clang compiler found; pass --cc with its path.")


def run(command: list[str], environment: dict[str, str]) -> None:
    subprocess.run(command, cwd=APP_ROOT, env=environment, check=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cc", help="Path to a GCC/Clang C compiler.")
    parser.add_argument("--cxx", help="Path to a matching C++ compiler; inferred for gcc/clang.")
    arguments = parser.parse_args()

    cc = compiler_path(arguments.cc, ("clang", "gcc", "cc"))
    executable_suffix = ".exe" if os.name == "nt" else ""
    cxx_name = "clang++" if "clang" in cc.name else "g++" if "gcc" in cc.name else "c++"
    sibling_cxx = cc.with_name(cxx_name + executable_suffix)
    cxx = compiler_path(arguments.cxx or (str(sibling_cxx) if sibling_cxx.is_file() else None), (cxx_name,))

    output = OUTPUT_ROOT.resolve()
    if not output.is_relative_to((APP_ROOT / ".dart_tool").resolve()):
        raise SystemExit("Verification output must stay inside the app's .dart_tool directory.")

    output.mkdir(parents=True, exist_ok=True)
    executable = output / ("audio_facade_test" + executable_suffix)
    environment = dict(os.environ)
    environment["PATH"] = str(cc.parent) + os.pathsep + str(cxx.parent) + os.pathsep + environment.get("PATH", "")

    target = subprocess.run(
        [str(cc), "-dumpmachine"],
        cwd=APP_ROOT,
        env=environment,
        check=True,
        capture_output=True,
        text=True,
    ).stdout.strip()
    warnings = ["-Wall", "-Wextra", "-Werror"]
    # PE targets cannot enforce Mach-O visibility. Apple builds must verify exports.
    if "mingw" in target:
        warnings.append("-Wno-attributes")

    run(
        [
            str(cc), "-std=c11", *warnings, "-UNDEBUG", "-I", str(NATIVE_ROOT),
            str(NATIVE_ROOT / "phonolite_audio.c"), str(TEST_ROOT / "audio_facade_test.c"),
            "-o", str(executable),
        ],
        environment,
    )
    run(
        [
            str(cxx), "-std=c++11", "-Wall", "-Wextra", "-Werror", "-I", str(NATIVE_ROOT),
            "-fsyntax-only", str(TEST_ROOT / "audio_header_test.cpp"),
        ],
        environment,
    )
    run([str(executable)], environment)

    result = {
        "facade_forwarding_cases": 14,
        "cpp_header_type_assertions": 14,
        "compiler_target": target,
        "apple_audio_implementations_compiled": False,
        "apple_symbol_visibility_verified": False,
    }
    (output / "facade_verification.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print("C++ public-header ABI type checks passed. AudioQueue/CoreAudio and Apple linking remain unverified.")


if __name__ == "__main__":
    main()
