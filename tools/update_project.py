#!/usr/bin/env python3
"""Update an existing Quest Photo project without replacing local Android settings.

Run from the extracted source: py tools/update_project.py C:\\path\\to\\QuestPhoto
Dry-run is the default; add --apply to write files. Python standard library only.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
from pathlib import Path
import re
import shutil
import sys
import uuid

VERSION = "0.3.0"
MIN_VERSION_CODE = 3
SOURCE = Path(__file__).resolve().parents[1]
DIRECTORIES = {"scripts", "scenes", "shaders", "assets", "models", "tools", "tests", "docs", "android_ai"}
ROOT_FILES = {"README.md", "LICENSE", "openxr_action_map.tres", "icon.svg", "THIRD_PARTY_NOTICES.md"}
SKIP_PARTS = {".git", ".godot", ".gradle", ".build", "build", "__pycache__", ".venv", "venv", "node_modules"}
KEY_SUFFIXES = {".keystore", ".jks", ".p12", ".pem", ".key", ".apk", ".aab", ".pyc"}


def set_option(section: str, key: str, value: str) -> str:
    pattern = re.compile(r"^" + re.escape(key) + r"\s*=.*$", re.MULTILINE)
    new = key + "=" + value
    if pattern.search(section):
        return pattern.sub(lambda _: new, section)
    return section.rstrip() + "\n" + new + "\n\n"


def sections(text: str) -> list[tuple[str, str]]:
    parts = re.split(r"(?m)^(\[[^\]\n]+\])\s*\n", text)
    result = [("", parts[0])]
    result.extend((parts[i], parts[i + 1]) for i in range(1, len(parts), 2))
    return result


def join_sections(values: list[tuple[str, str]]) -> str:
    return "".join((header + "\n" if header else "") + body for header, body in values)


def update_project_metadata(text: str) -> str:
    values = sections(text)
    found = False
    for index, (header, body) in enumerate(values):
        if header == "[application]":
            values[index] = (header, set_option(body, "config/version", '"' + VERSION + '"'))
            found = True
    if not found:
        raise ValueError("Existing project.godot has no [application] section; refusing replacement.")
    return join_sections(values)


def update_export_metadata(text: str, enable_plugin: bool) -> str:
    values = sections(text)
    android = set()
    for header, body in values:
        match = re.fullmatch(r"\[preset\.(\d+)\]", header)
        if match and re.search(r'^platform\s*=\s*"Android"\s*$', body, re.MULTILINE):
            android.add(match.group(1))
    for index, (header, body) in enumerate(values):
        match = re.fullmatch(r"\[preset\.(\d+)\]", header)
        if match and match.group(1) in android:
            old_filter = re.search(r'^include_filter\s*=\s*"([^"]*)"\s*$', body, re.MULTILINE)
            filters = [item.strip() for item in old_filter.group(1).split(",") if item.strip()] if old_filter else []
            for extension in ("*.bin", "*.json"):
                if extension not in filters:
                    filters.append(extension)
            values[index] = (header, set_option(body, "include_filter", '"' + ",".join(filters) + '"'))
    for index, (header, body) in enumerate(values):
        match = re.fullmatch(r"\[preset\.(\d+)\.options\]", header)
        if not match or match.group(1) not in android:
            continue
        old_code = re.search(r"^version/code\s*=\s*(\d+)\s*$", body, re.MULTILINE)
        old_name = re.search(r'^version/name\s*=\s*"([^"]*)"\s*$', body, re.MULTILINE)
        code = int(old_code.group(1)) if old_code else 0
        if not old_name or old_name.group(1) != VERSION:
            code += 1
        body = set_option(body, "version/code", str(max(MIN_VERSION_CODE, code)))
        body = set_option(body, "version/name", '"' + VERSION + '"')
        if enable_plugin:
            body = set_option(body, "plugins/QuestDepth", "true")
        values[index] = (header, body)
    return join_sections(values)


def eligible(path: Path) -> bool:
    if any(part in SKIP_PARTS or part.startswith(".quest-photo-backup-") for part in path.parts):
        return False
    if path.suffix.lower() in KEY_SUFFIXES or path.is_absolute():
        return False
    if len(path.parts) == 1:
        return path.name in ROOT_FILES
    if path.parts[:2] == ("android", "plugins"):
        return True
    return path.parts[0] in DIRECTORIES


def plan_update(source: Path, target: Path) -> dict[Path, bytes]:
    source = source.resolve()
    target = target.resolve()
    if source == target or source in target.parents or target in source.parents:
        raise ValueError("Extract the update beside your existing project, not inside it.")
    if not (target / "project.godot").is_file():
        raise ValueError("Target must be your EXISTING project directory containing project.godot.")
    for name in ("project.godot", "export_presets.cfg"):
        if (target / name).is_symlink():
            raise ValueError(f"Refusing symlink configuration: {name}")
    changes = {}
    for path in sorted(source.rglob("*")):
        relative = path.relative_to(source)
        if path.is_symlink() or not path.is_file() or not eligible(relative):
            continue
        destination = target / relative
        if destination.is_symlink() or target not in destination.resolve().parents:
            raise ValueError(f"Refusing symlink or path outside target: {relative}")
        content = path.read_bytes()
        if not destination.exists() or destination.read_bytes() != content:
            changes[relative] = content
    project = target / "project.godot"
    old = project.read_bytes()
    updated = update_project_metadata(old.decode("utf-8-sig")).encode("utf-8")
    if updated != old:
        changes[Path("project.godot")] = updated
    export = target / "export_presets.cfg"
    if export.exists():
        old = export.read_bytes()
        enable_plugin = all((source / "android/plugins" / name).is_file() for name in ("QuestDepth.gdap", "QuestDepth.aar", "onnxruntime-android-1.22.0.aar"))
        updated = update_export_metadata(old.decode("utf-8-sig"), enable_plugin).encode("utf-8")
        if updated != old:
            changes[Path("export_presets.cfg")] = updated
    return changes


def apply_update(target: Path, changes: dict[Path, bytes]) -> Path | None:
    if not changes:
        return None
    # Backup is outside the project, so it cannot accidentally enter the APK.
    backup = target.parent / (target.name + "-backup-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8])
    backup.mkdir()
    manifest = []
    for relative in changes:
        destination = target / relative
        if destination.exists():
            saved = backup / relative
            saved.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(destination, saved)
            manifest.append("REPLACED " + relative.as_posix())
        else:
            manifest.append("ADDED " + relative.as_posix())
    (backup / "UPDATE-MANIFEST.txt").write_text("\n".join(manifest) + "\n", encoding="utf-8")
    for relative, content in changes.items():
        destination = target / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        temporary = destination.with_name(destination.name + ".update-" + uuid.uuid4().hex)
        temporary.write_bytes(content)
        temporary.replace(destination)
    return backup


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("target", type=Path, help="Existing working Godot project directory")
    parser.add_argument("--apply", action="store_true", help="Write changes after backing up existing files")
    args = parser.parse_args()
    try:
        target = args.target.resolve()
        changes = plan_update(SOURCE, target)
        for path in changes:
            print("UPDATE " + path.as_posix())
        print(f"{len(changes)} changed files. Local Android build, SDK paths, package and keys preserved.")
        if args.apply:
            backup = apply_update(target, changes)
            print("Backup: " + str(backup) if backup else "Already up to date.")
        else:
            print("Dry run only. Close Godot and repeat with --apply to update.")
        print("AI requires the compiled QuestDepth plugin and packaged ONNX models. See docs/UPDATE_030.md.")
        return 0
    except (ValueError, OSError, UnicodeError) as error:
        print("Update stopped: " + str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
