"""Run the engine-independent Space Garden test suites with the standalone Luau CLI.

The modules under src/ are written for Roblox, so each suite is wrapped in a small
harness that stubs the few engine globals the module touches at load time
(game, task, Color3, require). The test code itself is the RunTests function that
ships inside each module, unchanged.

Usage:
    python tests/cli/run_cli_tests.py [--luau path/to/luau]

Requires the Luau CLI (https://github.com/luau-lang/luau/releases) on PATH or
passed with --luau.
"""
from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "src"

PRELUDE = """
local task = {wait = function() end, spawn = function() end, defer = function() end}
local Color3 = {fromRGB = function(r, g, b) return {R = r / 255, G = g / 255, B = b / 255} end}
"""

RUNNER = """
local result = {call}
print("PASSED " .. tostring(result.passed))
for _, check in ipairs(result.checks or {{}}) do print("  " .. check) end
"""


def module(path: Path) -> str:
    """Wrap a ModuleScript so it can be inlined as an expression."""
    return "(function()\n" + path.read_text(encoding="utf-8-sig") + "\nend)()"


def harness_global_progress() -> str:
    body = module(SRC / "ServerStorage" / "SpaceGardenGlobal.luau")
    return PRELUDE + f"local GlobalProgress = {body}\n" + RUNNER.format(call="GlobalProgress.RunTests()")


def harness_blueprints() -> str:
    body = module(SRC / "ServerStorage" / "SpaceGardenBlueprints.luau")
    return PRELUDE + f"local Blueprints = {body}\n" + RUNNER.format(call="Blueprints.RunTests()")


def harness_decorations() -> str:
    catalog = module(SRC / "ReplicatedStorage" / "SpaceGarden" / "DecorCatalog.luau")
    decorations = module(SRC / "ServerStorage" / "SpaceGardenDecorations.luau")
    stubs = f"""
local Catalog = {catalog}
local folder = {{}}
function folder:WaitForChild(name) return name == "DecorCatalog" and Catalog or folder end
local game = {{GetService = function() return folder end}}
local require = function(value) return value end
"""
    return PRELUDE + stubs + f"local Decorations = {decorations}\n" + RUNNER.format(call="Decorations.RunValidationTests()")


SUITES = {
    "GlobalProgress (monthly counters, ranking)": harness_global_progress,
    "Blueprints (shareable design codes)": harness_blueprints,
    "Decorations (design validation)": harness_decorations,
}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--luau", default=shutil.which("luau") or "luau", help="path to the luau executable")
    args = parser.parse_args()

    total, failed = 0, 0
    with tempfile.TemporaryDirectory() as tmp:
        for name, build in SUITES.items():
            file = Path(tmp) / (name.split()[0] + ".luau")
            file.write_text(build(), encoding="utf-8")
            proc = subprocess.run([args.luau, str(file)], capture_output=True, text=True, encoding="utf-8")
            output = (proc.stdout + proc.stderr).strip()
            passed = next((int(line.split()[1]) for line in output.splitlines() if line.startswith("PASSED ")), None)
            if proc.returncode != 0 or passed is None:
                failed += 1
                print(f"FAIL  {name}\n{output}\n")
            else:
                total += passed
                print(f"ok    {name}: {passed} checks")
    print(f"\n{total} checks passed, {failed} suite(s) failed")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
