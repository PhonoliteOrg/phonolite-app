"""Check or format handwritten Android Kotlin with the project's pinned ktlint."""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess
import urllib.request


APP_ROOT = Path(__file__).resolve().parents[2]
KTLINT_VERSION = "1.7.1"
KTLINT_SHA256 = "5f3de4ee4014137b05c72ed68eb46fe686aeb11fbdef27faf77f55d51c1b2536"
KTLINT_URL = (
    "https://repo.maven.apache.org/maven2/com/pinterest/ktlint/ktlint-cli/"
    f"{KTLINT_VERSION}/ktlint-cli-{KTLINT_VERSION}-all.jar"
)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--format", action="store_true", help="Apply formatting instead of checking")
    parser.add_argument("--java", type=Path, default=shutil.which("java"))
    args = parser.parse_args()
    if not args.java:
        parser.error("Java is required; configure PATH or pass --java")

    cache = APP_ROOT / ".dart_tool/android_tools"
    cache.mkdir(parents=True, exist_ok=True)
    formatter = cache / f"ktlint-{KTLINT_VERSION}.jar"
    if not formatter.exists():
        with urllib.request.urlopen(KTLINT_URL, timeout=60) as response:
            content = response.read()
        if hashlib.sha256(content).hexdigest() != KTLINT_SHA256:
            raise SystemExit("Downloaded ktlint checksum does not match the project pin")
        formatter.write_bytes(content)

    if hashlib.sha256(formatter.read_bytes()).hexdigest() != KTLINT_SHA256:
        raise SystemExit(f"Cached ktlint checksum does not match the project pin: {formatter}")

    sources = sorted((APP_ROOT / "android/app/src").rglob("*.kt"))
    scripts = sorted((APP_ROOT / "android").glob("*.gradle.kts"))
    scripts.extend(sorted((APP_ROOT / "android/app").glob("*.gradle.kts")))
    command = [str(args.java), "-jar", str(formatter)]
    if args.format:
        command.append("--format")
    command.extend(str(path.relative_to(APP_ROOT)) for path in [*sources, *scripts])

    raise SystemExit(subprocess.run(command, cwd=APP_ROOT).returncode)


if __name__ == "__main__":
    main()
