"""Run isolated headless checks; fail on Godot script errors even at exit code 0."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile

PROJECT = Path(__file__).resolve().parents[1]
LOGS = PROJECT / "build" / "checks"
LOGS.mkdir(parents=True, exist_ok=True)
GODOT = os.environ.get("GODOT_BIN", "godot")
# Editor debugging listeners cannot bind sockets in this sandbox. These exact
# infrastructure errors are permitted ONLY during import, never runtime tests.
EDITOR_INFRA_ERRORS = (
    'ERROR: Condition "_sock == -1" is true. Returning: FAILED',
    'ERROR: Condition "err != OK" is true. Returning: ERR_CANT_CREATE',
)

with tempfile.TemporaryDirectory(prefix="quest-photo-tests-") as temporary:
    env = dict(os.environ)
    for key, leaf in (("XDG_DATA_HOME", "data"), ("XDG_CONFIG_HOME", "config"), ("XDG_CACHE_HOME", "cache")):
        env[key] = str(Path(temporary) / leaf)
    base = [GODOT, "--headless", "--xr-mode", "off", "--path", str(PROJECT)]
    steps = [
        ("import", base + ["--editor", "--import", "--quit"]),
        ("assets", [sys.executable, "-m", "unittest", "discover", "-s", "tests", "-p", "test_*.py", "-v"]),
        ("core", base + ["--script", "res://tests/test_core.gd"]),
        ("export", base + ["--script", "res://tests/test_export.gd"]),
        ("formats", base + ["--script", "res://tests/test_formats.gd"]),
        ("layouts", base + ["--script", "res://tests/test_layouts.gd"]),
        ("ai_conversion", base + ["--script", "res://tests/test_ai_conversion.gd"]),
        ("depth_reprojection", base + ["--script", "res://tests/test_depth_reprojection.gd"]),
        ("export_protection", base + ["--script", "res://tests/test_export_protection.gd"]),
        ("storage", base + ["--script", "res://tests/test_storage.gd"]),
        ("gallery", base + ["--script", "res://tests/test_gallery.gd"]),
        ("viewer", base + ["--script", "res://tests/test_viewer.gd"]),
        ("grip_gallery", base + ["--script", "res://tests/test_grip_gallery.gd"]),
        ("integration", base + ["--script", "res://tests/test_integration.gd"]),
        ("startup", base + ["--quit-after", "10"]),
        ("build-script-syntax", ["bash", "-n", "tools/build_android.sh"]),
    ]
    if os.name == "nt":
        steps = [(name, command) for name, command in steps if name != "build-script-syntax"]
    for name, command in steps:
        print(f"Running {name}…", flush=True)
        try:
            result = subprocess.run(command, cwd=PROJECT, env=env, text=True,
                                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=120)
        except subprocess.TimeoutExpired:
            raise SystemExit(f"FAIL: {name} exceeded 120 seconds")
        output = result.stdout
        (LOGS / f"{name}.log").write_text(output)
        errors = [line for line in output.splitlines()
                  if ("ERROR:" in line or "Parse Error" in line)
                  and not (name == "import" and line in EDITOR_INFRA_ERRORS)]
        if result.returncode or errors:
            print(output)
            raise SystemExit(f"FAIL: {name} (exit {result.returncode}); see {LOGS}")
        if name != "import":
            print(output.rstrip(), flush=True)
        elif any(line in output for line in EDITOR_INFRA_ERRORS):
            print("Import completed; sandbox blocked editor debug sockets (logged).")
    print("PASS: headless checks. Graphics, real OpenXR, Android APK and Quest hardware remain unverified.")
