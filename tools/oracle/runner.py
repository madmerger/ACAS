#!/usr/bin/env python3
"""Build and run the legacy oracle in disposable, isolated directories."""

import argparse
import difflib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

import jsonschema
import pexpect
import pyte

from converters import data_records, report_json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def load(path):
    return json.loads(path.read_text())


def render(value):
    return json.dumps(value, indent=2, ensure_ascii=False, sort_keys=True) + "\n"


def build(destination):
    destination.mkdir(parents=True, exist_ok=False)
    paths = subprocess.check_output(["git", "ls-files", "-z"], cwd=ROOT).decode().split("\0")
    for name in paths:
        if name and not name.startswith(("tools/", ".git")):
            target = destination / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(ROOT / name, target)
    with (destination / "build.log").open("w") as log:
        subprocess.run(["bash", "./comp-all.sh"], cwd=destination, stdout=log,
                       stderr=subprocess.STDOUT, check=True)
    if re.search(r"\berror:", (destination / "build.log").read_text(), re.I):
        raise RuntimeError(f"Legacy build failed; see {destination / 'build.log'}")
    subprocess.run(["cobc", "-x", "-free", "-I", str(ROOT / "sales"),
                    "-I", str(ROOT / "copybooks"), "-o", str(destination / "oracle-bridge"),
                    str(HERE / "bridge.cbl")], check=True)
    print("BUILD legacy app + oracle bridge OK (ISAM via installed GnuCOBOL)")


def seed(work, executable, fixture, env):
    rows = []
    for record in fixture["analysis"]:
        values = [record["ledger"], record["code"], f'{record["gl"]:06d}',
                  record["description"], record["print"]]
        for value, limit in zip(values, [1, 2, 6, 24, 3]):
            if len(value) > limit or any(c in value for c in "|\r\n"):
                raise ValueError("Fixture field exceeds COBOL layout or contains a delimiter")
        rows.append("A|" + "|".join(values))
    for record in fixture["suppliers"]:
        values = [record["code"], record["name"]]
        for value, limit in zip(values, [7, 30]):
            if len(value) > limit or any(c in value for c in "|\r\n"):
                raise ValueError("Invalid supplier fixture")
        rows.append("P|" + "|".join(values))
    (work / "seed.txt").write_text("\n".join(rows) + "\n")
    subprocess.run([str(executable), "seed"], cwd=work, env=env, check=True)


def run_case(case, build_dir, output, fixture):
    work = Path(tempfile.mkdtemp(prefix=case["id"] + "-", dir=output))
    env = dict(os.environ, TERM="vt100", LC_ALL="C", TZ="UTC",
               COB_LIBRARY_PATH=os.pathsep.join(str(build_dir / directory)
                                               for directory in ("sales", "common")),
               PATH=str(work) + os.pathsep + os.environ["PATH"])
    # Keep the legacy print file, never contact a host's printer or delete it.
    (work / "lpr").write_text("#!/bin/sh\ntest -s prt-1\n")
    (work / "lpr").chmod(0o755)
    executable = build_dir / "oracle-bridge"
    seed(work, executable, fixture, env)
    screen = pyte.Screen(80, 24)
    stream = pyte.Stream(screen)
    screens = []
    with (work / "terminal.log").open("w") as transcript:
        class Capture:
            def write(self, text):
                transcript.write(text)
                stream.feed(text)

            def flush(self):
                transcript.flush()

        child = pexpect.spawn(str(executable), ["run"], cwd=work, env=env,
                              encoding="utf-8", timeout=10, dimensions=(24, 80))
        child.logfile_read = Capture()
        try:
            for step in case["steps"]:
                child.expect_exact(step["expect"])
                if "capture" in step:
                    screens.append({"name": step["capture"],
                                    "lines": [re.sub(r"\d{4}/\d{2}/\d{2}", "<DATE>",
                                                     line.rstrip()) for line in screen.display]})
                child.send(step["send"])
            child.expect(pexpect.EOF)
            child.close()
            if child.exitstatus != 0:
                raise RuntimeError(f"Legacy exited with status {child.exitstatus}")
        finally:
            child.close(force=True)
    subprocess.run([str(executable), "dump"], cwd=work, env=env, check=True)
    result = {"id": case["id"], "data": data_records((work / "dump.txt").read_text()),
              "screens": screens, "reports": {}}
    for report in case["outputs"]["reports"]:
        result["reports"][report] = report_json((work / report).read_text())
    (output / (case["id"] + ".json")).write_text(render(result))
    print(f"RUN {case['id']} OK; terminal, ISAM files and printer output: {work}")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases", type=Path, default=HERE / "cases.json")
    parser.add_argument("--output", type=Path, default=HERE / "results")
    parser.add_argument("--compare", action="store_true")
    args = parser.parse_args()
    cases = load(args.cases)
    jsonschema.validate(cases, load(HERE / "cases.schema.json"))
    ids = [case["id"] for case in cases["cases"]]
    if len(ids) != len(set(ids)):
        raise ValueError("Duplicate case ids")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    build_dir = Path(tempfile.mkdtemp(prefix="build-", dir=output)) / "app"
    build(build_dir)
    failed = False
    for case in cases["cases"]:
        actual = render(run_case(case, build_dir, output, load(HERE / "fixture.json")))
        if args.compare:
            expected = (HERE / "golden" / (case["id"] + ".json")).read_text()
            if actual != expected:
                print("".join(difflib.unified_diff(expected.splitlines(True),
                                                  actual.splitlines(True),
                                                  fromfile="golden", tofile="actual")))
                failed = True
            else:
                print(f"COMPARE {case['id']} MATCH")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
