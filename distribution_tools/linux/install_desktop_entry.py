"""Register a built Phonolite bundle in the current user's application menu and dock.

Run again after moving the bundle or choosing another build. No application is launched.
"""

from __future__ import annotations

import argparse
import base64
import os
from pathlib import Path


APPLICATION_ID = "com.phonoliteorg.phonolite_app"
ICON_PATH = Path("data/flutter_assets/assets/images/phonolite-logo-nobackground.png")


def desktop_string(value: str) -> str:
    if any(character in value for character in ("\0", "\n", "\r")):
        raise ValueError("Desktop entry paths cannot contain NUL or newline characters.")

    return value.replace("\\", "\\\\").replace("\t", r"\t")


def exec_argument(executable: Path) -> str:
    # Exec arguments are unescaped twice: first as desktop strings, then as
    # arguments. Percent signs must also survive desktop field-code expansion.
    argument = str(executable)
    for character in ("\\", '"', "`", "$"):
        argument = argument.replace(character, "\\" + character)

    return desktop_string('"' + argument.replace("%", "%%") + '"')


def desktop_icon_svg(source: Path) -> str:
    # Preserve the existing logo with a two-pixel inset at a 48-pixel dock size.
    image = base64.b64encode(source.read_bytes()).decode("ascii")

    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">\n'
        '  <image x="2" y="2" width="44" height="44" preserveAspectRatio="xMidYMid meet" '
        f'href="data:image/png;base64,{image}"/>\n'
        '</svg>\n'
    )


def install_desktop_entry(bundle: Path) -> Path:
    bundle = bundle.expanduser().resolve(strict=True)
    executable = bundle / "phonolite_app"
    icon = bundle / ICON_PATH

    if not executable.is_file() or not os.access(executable, os.X_OK):
        raise ValueError(f"The bundle does not contain an executable phonolite_app: {bundle}")

    if not icon.is_file():
        raise ValueError(f"The bundle does not contain the Phonolite logo: {icon}")

    data_home = Path(os.environ.get("XDG_DATA_HOME", ""))
    if not data_home.is_absolute():
        data_home = Path.home() / ".local/share"

    identity_file = bundle / "data/application-id"
    if not identity_file.is_file():
        raise ValueError("Rebuild the bundle to include its desktop application identity.")
    application_id = identity_file.read_text().strip()
    if application_id != APPLICATION_ID + ".devel":
        raise ValueError("Per-user registration is reserved for debug bundles; install release packages system-wide.")

    installed_icon = data_home / "icons/hicolor/scalable/apps" / f"{application_id}.svg"
    icon_contents = desktop_icon_svg(icon)
    contents = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Phonolite (Development)\n"
        # A fixed executable lets GIO discover the command even when the bundle
        # path contains spaces or percent field-code escapes. No shell is used.
        f"Exec=/usr/bin/env {exec_argument(executable)}\n"
        f"Icon={desktop_string(str(installed_icon))}\n"
        f"StartupWMClass={application_id}\n"
        "Terminal=false\n"
        "StartupNotify=false\n"
        "Categories=AudioVideo;Audio;Player;\n"
    )
    destination = data_home / "applications" / f"{application_id}.desktop"
    installed_icon.parent.mkdir(parents=True, exist_ok=True)
    installed_icon.write_text(icon_contents, encoding="utf-8")
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(contents, encoding="utf-8")

    return destination


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path, help="Built Flutter Linux bundle directory.")
    arguments = parser.parse_args()

    try:
        destination = install_desktop_entry(arguments.bundle)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Could not register Phonolite: {error}\n")

    print(f"Registered Phonolite: {destination}")


if __name__ == "__main__":
    main()
