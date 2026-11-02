#!/usr/bin/env python3
"""
Build package/qtxFunctional.pkg from src/*.pas and package/package.info.json.

A Quartex Pascal package is a zip archive holding the unit files and a
package.info.json manifest at the top level.

Usage:
    python tools/build-package.py                 # rebuild with the current version
    python tools/build-package.py 1.2.0.0 "Note"  # set a new version first

Install the result by copying package/qtxFunctional.pkg into
%APPDATA%\\qtx\\packages and restarting the Quartex Pascal IDE.
"""
import datetime
import glob
import json
import os
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "src")
MANIFEST = os.path.join(ROOT, "package", "package.info.json")
OUTPUT = os.path.join(ROOT, "package", "qtxFunctional.pkg")


def main() -> None:
    with open(MANIFEST, encoding="utf-8-sig") as f:
        manifest = json.load(f)

    if len(sys.argv) > 1:
        parts = sys.argv[1].split(".")
        if len(parts) != 4 or not all(p.isdigit() for p in parts):
            sys.exit("Version must look like 1.2.0.0")
        version = manifest["Version"]
        version["Major"], version["Minor"], version["Revision"], version["Build"] = parts
        version["Name"] = "Release " + sys.argv[1]
        version["Release"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        if len(sys.argv) > 2:
            version["Note"] = sys.argv[2]
        with open(MANIFEST, "w", encoding="utf-8") as f:
            json.dump(manifest, f, indent=4)

    units = sorted(glob.glob(os.path.join(SRC, "functional.*.pas")))
    if not units:
        sys.exit("No units found in src/")

    with zipfile.ZipFile(OUTPUT, "w", zipfile.ZIP_DEFLATED) as pkg:
        pkg.writestr("package.info.json", json.dumps(manifest, indent=4))
        for unit in units:
            pkg.write(unit, os.path.basename(unit))

    with zipfile.ZipFile(OUTPUT) as pkg:
        bad = pkg.testzip()
        if bad:
            sys.exit("Archive check failed at " + bad)

    print(f"Built {os.path.relpath(OUTPUT, ROOT)}: {manifest['Version']['Name']}, {len(units)} units")


if __name__ == "__main__":
    main()
