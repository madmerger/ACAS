"""ビルド済みの買掛元帳 XCUITest を実行し、Simulator の映像と時刻を保存する。"""
import argparse
import json
import os
import plistlib
import shutil
import signal
import subprocess
import time
import uuid
from pathlib import Path

from generate_fixtures import purchase_case_ids


def expected_reports(xctestrun, cases):
    run = plistlib.loads(xctestrun.read_bytes())
    if "TestConfigurations" in run:
        targets = [target for config in run["TestConfigurations"] for target in config["TestTargets"]]
        target = next(target for target in targets if target["BlueprintName"] == "ACASUITests")
    else:
        target = run["ACASUITests"]
    root = str(xctestrun.resolve().parent)
    host = target["TestHostPath"].replace("__TESTROOT__", root)
    bundle = target["TestBundlePath"].replace("__TESTHOST__", host).replace("__TESTROOT__", root)
    expected = set()
    for case in cases:
        fixture = json.loads((Path(bundle) / "fixtures" / f"{case}.json").read_text())
        equivalence = fixture.get("equivalence") or {}
        if not equivalence.get("outOfScope"):
            expected.update(Path(case) / Path(report).name
                            for report in (equivalence.get("reportDigests") or fixture["reports"]))
    return expected


def collect_reports(source, output, expected):
    if source.is_dir():
        shutil.copytree(source, output)
    return sorted(path for path in expected if not (output / path).is_file())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("udid")
    parser.add_argument("xctestrun", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("cases", nargs="*", help="再実行する PL-ID（省略時は全件）")
    args = parser.parse_args()
    available = purchase_case_ids()
    selected = ["PL-" + case.removeprefix("PL-") for case in args.cases] if args.cases else sorted(available)
    if len(available) != 74 or not set(selected) <= available:
        parser.error("ケース一覧が一致しません")
    expected = expected_reports(args.xctestrun, selected)
    cases = [case.removeprefix("PL-") for case in selected]
    args.output.mkdir()
    run_id = str(uuid.uuid4()).upper()
    video = args.output / "simulator.mp4"
    recorder = subprocess.Popen(
        ["xcrun", "simctl", "io", args.udid, "recordVideo", "--codec=h264", str(video)],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
    )
    try:
        for line in recorder.stdout:
            print(line.strip(), flush=True)
            if "Recording started" in line:
                break
        else:
            raise RuntimeError("Simulator の録画を開始できません")

        started = time.time()
        (args.output / "recording.json").write_text(
            json.dumps({"startEpoch": started, "cases": cases, "reportRunId": run_id}) + "\n")
        command = [
            "xcodebuild", "test-without-building", "-xctestrun", str(args.xctestrun),
            "-destination", f"platform=iOS Simulator,id={args.udid}", "-parallel-testing-enabled", "NO",
            "-collect-test-diagnostics", "never",
            "-resultBundlePath", str(args.output / "PL.xcresult"),
            *[f"-only-testing:ACASUITests/PurchaseFlows/testPL{case}" for case in cases],
        ]
        with (args.output / "xcodebuild.log").open("w", encoding="utf-8") as log:
            env = {**os.environ, "TEST_RUNNER_ACAS_PL_RUN_ID": run_id}
            status = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, env=env).returncode
    finally:
        if recorder.poll() is None:
            recorder.send_signal(signal.SIGINT)
        print(recorder.communicate(timeout=30)[0], end="", flush=True)
    container = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", args.udid, "jp.acas.ipad", "data"], text=True).strip())
    reports = container / "Library" / "Caches" / "pl-evidence" / run_id
    missing = collect_reports(reports, args.output / "reports", expected)
    if missing:
        print("試行の帳票を回収できませんでした: " + ", ".join(map(str, missing)), flush=True)
        status = status or 1
    raise SystemExit(status)


if __name__ == "__main__":
    main()
