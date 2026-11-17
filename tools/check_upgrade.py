"""Shows that code written for Relationship Web Lite runs unchanged on the full Relationship Web.

Usage: python -I tools/check_upgrade.py <godot console executable> <full version's addons/relationship_web>

Builds a scratch project with the full add-on in addons/relationship_web/ (an upgrade is exactly that folder
replaced), then runs Lite's core tests (every check must pass on the full version too) and Lite's demo (it must
load and draw with no errors, and without the Lite mark).
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
godot, full = sys.argv[1], sys.argv[2]

with tempfile.TemporaryDirectory() as tmp:
    shutil.copytree(full, os.path.join(tmp, "addons", "relationship_web"))
    for rel in ("tests/test_web.gd", "tests/test_web.tscn", "demo/lite_demo.gd", "demo/lite_demo.tscn", "demo/knight.png"):
        os.makedirs(os.path.join(tmp, os.path.dirname(rel)), exist_ok=True)
        shutil.copy(os.path.join(ROOT, rel), os.path.join(tmp, rel))
    with open(os.path.join(tmp, "project.godot"), "w", newline="\n") as f:
        f.write('config_version=5\n\n[application]\n\nconfig/name="Upgrade check"\n')
    subprocess.run([godot, "--headless", "--path", tmp, "--import"], capture_output=True, timeout=300)
    failed = 0
    tests = subprocess.run([godot, "--headless", "--path", tmp, "res://tests/test_web.tscn"], capture_output=True,
                           text=True, timeout=300)
    log = tests.stdout + tests.stderr
    summary = [l for l in log.splitlines() if "checks," in l]
    fails = [l for l in log.splitlines() if l.startswith("FAIL") or "SCRIPT ERROR" in l or "Parse Error" in l]
    ok = tests.returncode == 0 and summary and not fails
    failed += 0 if ok else 1
    print("  ok   " if ok else "  FAIL ", "Lite's core tests on the full version:", summary[-1].strip() if summary else "(no summary)")
    for l in fails[:10]:
        print("        ", l)
    demo = subprocess.run([godot, "--path", tmp, "--resolution", "1280x720", "res://demo/lite_demo.tscn", "--",
                           "--shots", "res://out"], capture_output=True, text=True, timeout=300)
    log = demo.stdout + demo.stderr
    errors = [l for l in log.splitlines() if "SCRIPT ERROR" in l or "Parse Error" in l]
    shots = os.path.exists(os.path.join(tmp, "out", "lite_pair.png"))
    ok = shots and not errors
    failed += 0 if ok else 1
    print("  ok   " if ok else "  FAIL ", "Lite's demo on the full version: loads, draws, saves its screenshots")
    for l in errors[:10]:
        print("        ", l)
    if shots:
        shutil.copy(os.path.join(tmp, "out", "lite_pair.png"), os.path.join(ROOT, "tests", "out", "upgrade_pair.png"))
    sys.exit(1 if failed else 0)
