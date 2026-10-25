#!/usr/bin/env python3
"""Copies the command-line tools biblioteca uses into the app bundle.

Runs as a build phase. The tools come from Homebrew on the build machine;
inside the app they live in Contents:

    Helpers/bin/        mutool, the DjVuLibre tools, tesseract
    Helpers/lib/        every non-system library they load, rewritten to load from here
    Resources/tessdata/ Tesseract's English, Greek and polytonic Greek models

(Helpers may hold only code, or the app cannot be signed; the models are data.)

so the built app needs nothing installed. Each file is re-signed ad hoc after
its load paths are rewritten, since rewriting breaks the signature.

Usage: bundle-tools.py APP_CONTENTS_DIR
"""

from __future__ import annotations

import hashlib
import os
import shutil
import subprocess
import sys

HOMEBREW = os.environ.get("HOMEBREW_PREFIX", "/opt/homebrew")
TOOLS = ["mutool", "ddjvu", "cjb2", "c44", "djvm", "djvused", "djvutxt", "tesseract"]
# Tesseract is only used where Apple Vision cannot read: Greek, with English beside it.
TESSDATA = ["eng", "ell", "grc"]
SYSTEM_PREFIXES = ("/usr/lib/", "/System/")


def run(*args: str) -> str:
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


def references(path: str) -> list[str]:
    """Libraries a Mach-O file loads, as written in it."""
    lines = run("otool", "-L", path).splitlines()[1:]
    return [line.strip().split(" (")[0] for line in lines]


def rpaths(path: str) -> list[str]:
    lines = run("otool", "-l", path).splitlines()
    return [lines[i + 2].split()[1] for i, line in enumerate(lines) if "LC_RPATH" in line]


def resolve(reference: str, loader: str) -> str | None:
    """The real file behind a reference, or None for a system library."""
    if reference.startswith(SYSTEM_PREFIXES):
        return None
    if not reference.startswith("@"):
        return os.path.realpath(reference)
    name = reference.split("/", 1)[1]
    folder = os.path.dirname(os.path.realpath(loader))
    candidates = [os.path.join(folder, name)] + [
        os.path.join(rpath.replace("@loader_path", folder), name) for rpath in rpaths(loader)
    ]
    found = next((c for c in candidates if os.path.exists(c)), None)
    if found is None:
        sys.exit(f"bundle-tools: cannot find {reference} loaded by {loader}")
    return os.path.realpath(found)


def library_closure(binaries: set[str]) -> dict[str, str]:
    """Every non-system library the binaries need: {name inside the app: real file}."""
    libraries, pending = {}, list(binaries)
    while pending:
        loader = pending.pop()
        for reference in references(loader):
            real = resolve(reference, loader)
            if real is None or real in binaries:
                continue
            name = os.path.basename(reference)
            if libraries.get(name) != real:
                libraries[name] = real
                pending.append(real)
    return libraries


def relink(path: str, prefix: str, libraries: dict[str, str]) -> None:
    """Points every bundled reference at the copy inside the app."""
    arguments = []
    for reference in references(path):
        name = os.path.basename(reference)
        if name in libraries and not reference.startswith(SYSTEM_PREFIXES):
            arguments += ["-change", reference, f"{prefix}/{name}"]
    if path.endswith(".dylib"):
        arguments += ["-id", f"@loader_path/{os.path.basename(path)}"]
    if arguments:
        run("install_name_tool", *arguments, path)
    run("codesign", "--force", "--sign", "-", path)


def fingerprint(files: list[str]) -> str:
    digest = hashlib.sha256()
    for path in sorted(files):
        digest.update(f"{path}:{os.path.getmtime(path)}".encode())
    return digest.hexdigest()


def main() -> None:
    contents = sys.argv[1]
    helpers = os.path.join(contents, "Helpers")
    tessdata = os.path.join(contents, "Resources", "tessdata")
    binaries = {tool: os.path.realpath(os.path.join(HOMEBREW, "bin", tool)) for tool in TOOLS}
    missing = [tool for tool, path in binaries.items() if not os.path.exists(path)]
    if missing:
        sys.exit(f"bundle-tools: install {', '.join(missing)} with Homebrew to build biblioteca")
    models = {f"{lang}.traineddata": os.path.realpath(f"{HOMEBREW}/share/tessdata/{lang}.traineddata")
              for lang in TESSDATA}
    # The "tsv" output config biblioteca asks Tesseract for.
    models["configs/tsv"] = os.path.realpath(f"{HOMEBREW}/share/tessdata/configs/tsv")
    libraries = library_closure(set(binaries.values()))

    stamp = os.path.join(contents, "Resources", ".bundled-tools-fingerprint")
    wanted = fingerprint(list(binaries.values()) + list(libraries.values()) + list(models.values()))
    if os.path.exists(stamp) and open(stamp).read() == wanted:
        print("bundle-tools: up to date")
        return

    for folder in (helpers, tessdata):
        shutil.rmtree(folder, ignore_errors=True)
    for folder in (os.path.join(helpers, "bin"), os.path.join(helpers, "lib"), tessdata):
        os.makedirs(folder)
    for name, real in libraries.items():
        target = os.path.join(helpers, "lib", name)
        shutil.copyfile(real, target)
        os.chmod(target, 0o755)
        relink(target, "@loader_path", libraries)
    for tool, real in binaries.items():
        target = os.path.join(helpers, "bin", tool)
        shutil.copyfile(real, target)
        os.chmod(target, 0o755)
        relink(target, "@loader_path/../lib", libraries)
    for name, real in models.items():
        target = os.path.join(tessdata, name)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        shutil.copyfile(real, target)
    with open(stamp, "w") as handle:
        handle.write(wanted)
    print(f"bundle-tools: {len(binaries)} tools, {len(libraries)} libraries, {len(TESSDATA)} OCR models")


if __name__ == "__main__":
    main()
