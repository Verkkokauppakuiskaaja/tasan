#!/usr/bin/env python3
"""
Fails when an app text has no English or Swedish translation.

Run after `xcodebuild -exportLocalizations`, which extracts every
text the code uses: a text missing from the String Catalogs, or
added there without a translation, shows up as untranslated in
the exported XLIFF files.
"""
import glob
import sys
import xml.etree.ElementTree as ET

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}
DONE = {"translated", "final", "signed-off", "needs-review-translation"}

problems = []
files = glob.glob(f"{sys.argv[1]}/**/*.xliff", recursive=True)
if not files:
    sys.exit(f"No XLIFF files under {sys.argv[1]}")

for path in files:
    root = ET.parse(path).getroot()
    for file in root.findall("x:file", NS):
        language = file.get("target-language")
        original = file.get("original", "")
        for unit in file.iter(f"{{{NS['x']}}}trans-unit"):
            if unit.get("translate") == "no":
                continue
            target = unit.find("x:target", NS)
            if target is None or target.get("state") not in DONE or not (target.text or "").strip():
                source = unit.find("x:source", NS)
                problems.append(f"{language} {original}: {unit.get('id')!r} ({source.text if source is not None else ''})")

print(f"Checked {len(files)} XLIFF files.")
if problems:
    print("Untranslated texts:")
    print("\n".join(sorted(set(problems))))
    sys.exit(1)
print("Every text has an English and a Swedish translation.")
