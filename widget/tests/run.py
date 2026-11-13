#!/usr/bin/env python3
"""Headless tests for the widget's behaviour (settings, sync, check-offs, notifications).

Loads the real contents/ui/main.qml against the stub Plasma modules in tests/stubs,
with the clock and the shell/notification services under test control. Needs `qml6`
(Qt 6 declarative tools); no Plasma session or network.

Usage: python3 widget/tests/run.py
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
WIDGET = os.path.dirname(HERE)


def find_qml():
    import glob
    cands = [shutil.which("qml6"), shutil.which("qml"), "/usr/lib/qt6/bin/qml"]
    cands += glob.glob("/usr/lib/*/qt6/bin/qml") + []
    for cand in cands:
        if cand and os.path.exists(cand):
            return cand
    sys.exit("qml6 not found (install Qt 6 declarative tools)")


def static_checks(src):
    """Cheap guards for mistakes that only show up in a live Plasma session."""
    problems = []
    # The config map's per-key change signals did not fire when the settings dialog
    # applied changes (zone changes never triggered a download). Watch values
    # through plain properties on the root item instead.
    if re.search(r"Connections\s*\{[^}]*target:\s*(root\.)?(cfg|Plasmoid\.configuration)", src):
        problems.append("main.qml reacts to config changes via Connections on the config map; "
                        "use `readonly property ... watchX: cfg.X` + `onWatchXChanged` instead")
    if "Plasmoid.icon:" not in src:
        problems.append("expected the `Plasmoid.icon:` line that the test harness strips")
    if "// ---- views ----" not in src:
        problems.append("missing the `// ---- views ----` marker that separates logic from views")
    return problems


def lint():
    """Run the real qmllint on the views when the Plasma QML modules are installed, so unknown
    properties and types in code the headless test strips (e.g. PlasmoidHeading) are caught."""
    tool = next((c for c in (shutil.which("qmllint"), shutil.which("qmllint6"), "/usr/lib/qt6/bin/qmllint") if c and os.path.exists(c)), None)
    qmldir = next((d for d in ("/usr/lib/qt6/qml", "/usr/lib/qt/qml") if os.path.isdir(os.path.join(d, "org/kde/plasma/extras"))), None)
    if not tool or not qmldir:
        print("skip - qmllint with Plasma modules not available")
        return []
    problems = []
    for rel in ("contents/ui/main.qml", "contents/ui/ConfigGeneral.qml"):
        out = subprocess.run([tool, "-I", qmldir, os.path.join(WIDGET, rel)], capture_output=True, text=True).stdout
        for line in out.splitlines():
            if line.startswith(("Warning", "Error")) and "[unqualified]" not in line:
                problems.append(line)
            elif line.startswith("Error"):
                problems.append(line)
    return problems


def main():
    src = open(os.path.join(WIDGET, "contents/ui/main.qml"), encoding="utf-8").read()
    problems = static_checks(src)
    if problems:
        print("\n".join("FAIL (static): " + p for p in problems))
        return 1

    lint_problems = lint()
    if lint_problems:
        print("\n".join("FAIL (qmllint): " + p for p in lint_problems))
        return 1
    print("ok  - qmllint")

    tmp = tempfile.mkdtemp(prefix="solat-test-")
    try:
        os.makedirs(os.path.join(tmp, "contents/ui"))
        shutil.copytree(os.path.join(WIDGET, "contents/code"), os.path.join(tmp, "contents/code"))
        # Strip the views (they need the real Kirigami/Plasma components) and the
        # Plasmoid.icon attached property; run the logic half only.
        lines = []
        for line in src.splitlines():
            if re.match(r"import org\.kde\.(kirigami|plasma\.components|plasma\.extras)\b", line):
                continue
            if line.strip().startswith("Plasmoid.icon:"):
                continue
            lines.append(line)
        logic = "\n".join(lines)
        logic = logic[: logic.index("    // ---- views ----")] + "}\n"
        # The test gives each widget its own config object so a finished widget can be cut off from it.
        logic = logic.replace("readonly property var cfg: Plasmoid.configuration", "property var cfg: Plasmoid.configuration")
        logic = re.sub(r"\bcfg\.([A-Z]\w*)", lambda m: "cfg." + m.group(1)[0].lower() + m.group(1)[1:], logic)
        logic = logic.replace("property bool useCurl: false", "property bool useCurl: true")  # no real network
        with open(os.path.join(tmp, "contents/ui/main.qml"), "w", encoding="utf-8") as f:
            f.write(logic)
        shutil.copy(os.path.join(HERE, "tst_widget.qml"), os.path.join(tmp, "tst_widget.qml"))

        env = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_FORCE_STDERR_LOGGING="1")
        proc = subprocess.run([find_qml(), "-I", os.path.join(HERE, "stubs"), os.path.join(tmp, "tst_widget.qml")],
                              env=env, capture_output=True, text=True, timeout=120)
        out = proc.stdout + proc.stderr
        for line in out.splitlines():
            line = re.sub(r"^qml: ", "", line)
            if line.startswith(("FAIL", "ok", "RESULT")) or re.search(r"error|Cannot|Unable|ReferenceError|TypeError", line, re.I):
                print(line)
        if "RESULT" not in out:
            print(out[-2000:])
            print("FAIL: test driver did not finish")
            return 1
        return proc.returncode
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
