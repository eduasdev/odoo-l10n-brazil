#!/usr/bin/env python3
"""Build-time sanity check, run inside the modified odoo image (addons
included).

Parses every module copied into /mnt/br-addons and warns (does not fail
the build) if a module's `depends` list names something that isn't core
Odoo and isn't among the addons we just copied in. Those modules would
otherwise just silently show as "Not Installable" in Odoo's Apps list,
with no obvious explanation, until the missing addon is added.

This only checks internal (Odoo module) dependencies. External (python)
dependencies are handled separately in the Dockerfile via the aggregated
requirements.txt + pip install.
"""
import ast
import glob
import os

ADDONS_DIR = "/mnt/br-addons"

# Core Odoo addons can live under slightly different paths depending on
# the python version baked into the base image; check all of them.
CORE_ADDON_GLOBS = [
    "/usr/lib/python3/dist-packages/odoo/addons",
    "/usr/lib/python3*/dist-packages/odoo/addons",
    "/usr/lib/python3/dist-packages/odoo/addons/*",  # no-op safety net
]


def list_subdirs(path):
    if not os.path.isdir(path):
        return set()
    return {n for n in os.listdir(path) if os.path.isdir(os.path.join(path, n))}


def main():
    available = set()
    for pattern in CORE_ADDON_GLOBS:
        for path in glob.glob(pattern):
            available |= list_subdirs(path)

    oca_modules = list_subdirs(ADDONS_DIR)
    available |= oca_modules

    if not oca_modules:
        print(f"[deps-verification] No addons found under {ADDONS_DIR}, skipping check.")
        return

    unresolved = []
    unparsed = []
    for mod in sorted(oca_modules):
        manifest_path = os.path.join(ADDONS_DIR, mod, "__manifest__.py")
        try:
            with open(manifest_path, encoding="utf-8") as f:
                manifest = ast.literal_eval(f.read())
        except Exception as exc:
            unparsed.append((mod, exc))
            continue
        for dep in manifest.get("depends", []):
            if dep not in available:
                unresolved.append((mod, dep))

    if unparsed:
        print(f"[deps-verification] {len(unparsed)} manifest(s) could not be parsed (skipped):")
        for mod, exc in unparsed:
            print(f"  - {mod}: {exc}")

    if unresolved:
        print(f"[deps-verification] MISSING: {len(unresolved)} module(s) have unmet dependencies (will show as 'Not Installable'):")
        for mod, dep in unresolved:
            print(f"  - {mod} -> requires '{dep}'")
    else:
        print(f"[deps-verification] OK: all {len(oca_modules)} module(s) have satisfied dependencies.")


if __name__ == "__main__":
    main()
