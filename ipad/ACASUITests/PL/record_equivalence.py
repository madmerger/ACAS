"""ビルド済みの買掛元帳 XCUITest を実行し、Simulator の映像と時刻を保存する。"""
import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import time
import uuid
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("udid")
    parser.add_argument("xctestrun", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("cases", nargs="*", help="再実行する PL-ID（省略時は全件）")
    args = parser.parse_args()
    source = Path(__file__).with_name("PurchaseFlows.swift").read_text(encoding="utf-8")
    available = re.findall(r"^    func testPL(\d{3})\(", source, re.MULTILINE)
    cases = [case.removeprefix("PL-") for case in args.cases] if args.cases else sorted(available)
    if len(set(available)) != 74 or not set(cases) <= set(available):
        parser.error("ケース一覧が一致しません")
    args.output.mkdir()
    run_id = str(uuid.uuid4()).upper()
    container = Path(subprocess.check_output(
        ["xcrun", "simctl", "get_app_container", args.udid, "jp.acas.ipad", "data"], text=True).strip())
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
        (args.output / "recording.json").write_text(json.dumps({"startEpoch": started, "cases": cases}) + "\n")
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
    reports = container / "Library" / "Caches" / "pl-evidence" / run_id
    if reports.is_dir():
        shutil.copytree(reports, args.output / "reports")
    raise SystemExit(status)


if __name__ == "__main__":
    main()
