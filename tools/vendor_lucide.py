"""Vendor the pinned official Lucide assets; never starts the app or a server.

Requires fonttools. Use --download to fetch the pinned npm archive, or --archive
to regenerate from an existing archive. Native iOS PNGs are generated separately
by render_lucide_native.cjs using sharp.
"""

import argparse
import base64
import hashlib
import io
import json
from pathlib import Path
import tarfile
import urllib.request
import xml.etree.ElementTree as ET

from fontTools import subset
from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parents[1]
VERSION = "1.52.0"
URL = f"https://registry.npmjs.org/lucide-static/-/lucide-static-{VERSION}.tgz"
INTEGRITY = "0zZYihAze4ZmUCcyNa9OkWYqn/Y5f9AdTh02AZIxMtP5ravcTTfoSIAnUPBH6ZvKxt+ZW28JB0ldzLRyD82fcw=="
ASSETS = ROOT / "assets/icons/lucide"
EXTRA_ICONS = {
    "chevron-down", "square-check", "square", "audio-lines", "antenna",
    "mic-vocal", "star", "bookmark", "ellipsis",
}
NATIVE_IOS = {
    "LucideAntenna": "antenna",
    "LucideDownload": "download",
    "LucideDisc3": "disc-3",
    "LucideMicVocal": "mic-vocal",
    "LucideListMusic": "list-music",
    "LucideHeart": "heart",
    "LucideHeartFilled": "heart",
    "LucideShuffle": "shuffle",
    "LucideEllipsis": "ellipsis",
    "LucideBookmark": "bookmark",
}
NATIVE_IOS_GRID = {
    "LucideDisc3Grid": "disc-3",
    "LucideListMusicGrid": "list-music",
    "LucideHeartFilledGrid": "heart",
    "LucideShuffleGrid": "shuffle",
    "LucideEllipsisGrid": "ellipsis",
}
NATIVE_ANDROID = {
    "ic_lucide_play": "play",
    "ic_lucide_pause": "pause",
    "ic_lucide_skip_back": "skip-back",
    "ic_lucide_skip_forward": "skip-forward",
    "ic_lucide_star": "star",
    "ic_lucide_star_selected": "star",
    "ic_lucide_audio_lines": "audio-lines",
}


def dart_name(name):
    first, *rest = name.split("-")
    return first + "".join(part.title() for part in rest)


def center_font_glyphs(font):
    # The upstream font has full-em advances but left-aligned outlines. Flutter
    # centers the advance cell, so narrow glyphs otherwise look far off-center.
    em = font["head"].unitsPerEm
    glyf = font["glyf"]
    glyphs = font.getGlyphSet()
    for name in font.getGlyphOrder():
        pen = BoundsPen(glyphs)
        glyphs[name].draw(pen)
        if pen.bounds is None:
            font["hmtx"][name] = (em, 0)
            continue
        glyph = glyf[name]
        if glyph.isComposite():
            raise ValueError(f"Unexpected composite Lucide glyph: {name}")
        left, bottom, right, top = pen.bounds
        glyph.coordinates.translate((
            round((em - left - right) / 2),
            round((em - bottom - top) / 2),
        ))
        glyph.recalcBounds(glyf)
        font["hmtx"][name] = (em, glyph.xMin)

    # Match the visible square to the font's line box on every platform.
    font["hhea"].ascent = em
    font["hhea"].descent = 0
    font["hhea"].lineGap = 0
    os2 = font["OS/2"]
    os2.sTypoAscender = em
    os2.sTypoDescender = 0
    os2.sTypoLineGap = 0
    os2.usWinAscent = em
    os2.usWinDescent = 0
    os2.xAvgCharWidth = em


def svg_path(element):
    tag = element.tag.split("}")[-1]
    a = element.attrib
    if tag == "path":
        return a["d"]
    if tag == "line":
        return f'M{a["x1"]} {a["y1"]}L{a["x2"]} {a["y2"]}'
    if tag in ("polyline", "polygon"):
        points = a["points"].replace(",", " ").split()
        return "M" + "L".join(" ".join(points[i:i + 2]) for i in range(0, len(points), 2)) + ("Z" if tag == "polygon" else "")
    if tag == "rect":
        x, y = float(a.get("x", 0)), float(a.get("y", 0))
        w, h = float(a["width"]), float(a["height"])
        rx = min(float(a.get("rx", 0)), w / 2)
        ry = min(float(a.get("ry", rx)), h / 2)
        if not rx or not ry:
            return f"M{x} {y}h{w}v{h}h{-w}Z"
        return (f"M{x + rx} {y}H{x + w - rx}Q{x + w} {y} {x + w} {y + ry}"
                f"V{y + h - ry}Q{x + w} {y + h} {x + w - rx} {y + h}"
                f"H{x + rx}Q{x} {y + h} {x} {y + h - ry}V{y + ry}Q{x} {y} {x + rx} {y}Z")
    if tag in ("circle", "ellipse"):
        cx, cy = float(a["cx"]), float(a["cy"])
        rx, ry = float(a.get("rx", a.get("r"))), float(a.get("ry", a.get("r")))
        return f"M{cx - rx} {cy}a{rx} {ry} 0 1 0 {2 * rx} 0a{rx} {ry} 0 1 0 {-2 * rx} 0"
    raise ValueError(f"Unsupported native SVG element: {tag}")


def android_vector(svg, filled=False):
    ns = "http://schemas.android.com/apk/res/android"
    ET.register_namespace("android", ns)
    a = lambda name: f"{{{ns}}}{name}"
    vector = ET.Element("vector", {
        a("width"): "24dp", a("height"): "24dp",
        a("viewportWidth"): "24", a("viewportHeight"): "24",
    })
    root = ET.fromstring(svg)
    for element in root:
        ET.SubElement(vector, "path", {
            a("pathData"): svg_path(element),
            a("fillColor"): "#FFFFFFFF" if filled else "#00000000",
            a("strokeColor"): "#FFFFFFFF", a("strokeWidth"): "2",
            a("strokeLineCap"): "round", a("strokeLineJoin"): "round",
        })
    ET.indent(vector)
    return '<?xml version="1.0" encoding="utf-8"?>\n<!-- Lucide ' + VERSION + '; see assets/icons/lucide/LICENSE. -->\n' + ET.tostring(vector, encoding="unicode") + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--archive", type=Path, default=ROOT / f".dart_tool/lucide-static-{VERSION}.tgz")
    parser.add_argument("--download", action="store_true")
    args = parser.parse_args()
    if args.download:
        data = urllib.request.urlopen(URL, timeout=60).read()
        args.archive.parent.mkdir(parents=True, exist_ok=True)
        args.archive.write_bytes(data)
    else:
        data = args.archive.read_bytes()
    if base64.b64encode(hashlib.sha512(data).digest()).decode() != INTEGRITY:
        raise ValueError("Lucide archive integrity mismatch")

    mapping = json.loads((ROOT / "tools/lucide_mapping.json").read_text())
    with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as archive:
        read = lambda name: archive.extractfile("package/" + name).read()
        codepoints = json.loads(read("font/codepoints.json"))
        names = sorted(set(mapping.values()) | EXTRA_ICONS)
        ASSETS.mkdir(parents=True, exist_ok=True)
        for name in names:
            (ASSETS / f"{name}.svg").write_bytes(read(f"icons/{name}.svg"))
        (ASSETS / "heart-filled.svg").write_text(
            (ASSETS / "heart.svg").read_text().replace('fill="none"', 'fill="currentColor"'),
            encoding="utf-8",
        )
        (ASSETS / "LICENSE").write_bytes(read("LICENSE"))
        font = TTFont(io.BytesIO(read("font/lucide.ttf")))

    options = subset.Options()
    options.glyph_names = True
    subsetter = subset.Subsetter(options=options)
    subsetter.populate(unicodes=[codepoints[name] for name in names])
    subsetter.subset(font)
    center_font_glyphs(font)
    font.save(ASSETS / "PhonoliteLucide.ttf")
    if not all(codepoints[name] in font.getBestCmap() for name in names):
        raise ValueError("Missing icon glyph in local font")

    dart = [
        "// Generated by tools/vendor_lucide.py from lucide-static " + VERSION + ".",
        "// SVG sources and the combined ISC/MIT license are vendored locally.",
        "import 'package:flutter/foundation.dart';",
        "import 'package:flutter/widgets.dart';",
        "import 'package:flutter/services.dart';",
        "", "abstract final class PhonoliteIcons {",
        "  static const fontFamily = 'PhonoliteLucide';", "",
    ]
    for name in names:
        direction = ", matchTextDirection: true" if name in ("chevron-left", "chevron-right") else ""
        dart.append(f"  static const {dart_name(name)} = IconData(0x{codepoints[name]:x}, fontFamily: fontFamily{direction});")
    dart += [
        "", "  static void registerLicense() {",
        "    LicenseRegistry.addLicense(() async* {",
        "      yield LicenseEntryWithLineBreaks(",
        "        const ['Lucide'],",
        "        await rootBundle.loadString('assets/icons/lucide/LICENSE'),",
        "      );", "    });", "  }", "}", "",
    ]
    (ROOT / "lib/widgets/ui/phonolite_icons.dart").write_text("\n".join(dart), encoding="utf-8")
    manifest = {
        "package": "lucide-static", "version": VERSION, "source": URL,
        "integrity": "sha512-" + INTEGRITY,
        "font_family": "PhonoliteLucide", "branding": "Original Phonolite logo retained",
        "material_to_lucide": mapping,
        "icons": {name: {"dart": dart_name(name), "codepoint": codepoints[name]} for name in names},
        "ios_assets": NATIVE_IOS, "ios_grid_assets": NATIVE_IOS_GRID,
        "android_drawables": NATIVE_ANDROID,
        "notes": [
            "Lucide uses outline icons. Existing active colors distinguish liked, shuffle and selected navigation states.",
            "Liked heart variants in Flutter and native controls use the same Lucide path with a filled interior.",
            "Native liked star variants use the same Lucide path with a filled interior.",
            "Checkboxes retain Flutter interaction/semantics, with local square/square-check glyphs.",
            "Font glyphs are centered in square advance cells with zero line gap.",
            "The main player retains its original filled Material play/pause icons.",
            "The now-playing indicator retains its original independently animated bars.",
        ],
    }
    (ASSETS / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    (ASSETS / "NOTICE.txt").write_text(
        f"Lucide {VERSION}\nOfficial source: https://lucide.dev/guide/static\n"
        "The app bundles these SVGs and a subset of the official icon font for offline use.\n"
        "The font subset centers each glyph within its square advance cell.\n"
        "heart-filled.svg is a Phonolite variant of heart.svg with a filled interior.\n"
        "LICENSE contains the Lucide ISC and inherited Feather MIT notices.\n"
        "manifest.json records the full replacement mapping and package integrity.\n"
        "Regenerate: python tools/vendor_lucide.py --download\n"
        "Then: node tools/render_lucide_native.cjs <path-to-sharp-module>\n"
        "Finally: dart format lib/widgets/ui/phonolite_icons.dart\n"
        "Original Phonolite branding and launcher assets are retained.\n", encoding="utf-8")

    drawable = ROOT / "android/app/src/main/res/drawable"
    drawable.mkdir(parents=True, exist_ok=True)
    for resource, name in NATIVE_ANDROID.items():
        (drawable / f"{resource}.xml").write_text(
            android_vector((ASSETS / f"{name}.svg").read_text(), resource.endswith("_selected")), encoding="utf-8")
    print(f"Vendored {len(names)} Lucide SVGs, {len(mapping)} mappings, local font and Android vectors.")


if __name__ == "__main__":
    main()
