"""実行録画を開始時刻と同期させ、H.264 の MP4 一本にまとめる。"""
import argparse
import json
import re
import subprocess
from datetime import datetime
from pathlib import Path


def probe(video):
    raw = subprocess.check_output([
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=codec_name,width,height:format=duration", "-of", "json", str(video),
    ])
    info = json.loads(raw)
    stream = info["streams"][0]
    if stream["codec_name"] != "h264" or min(stream["width"], stream["height"]) < 720 or max(
            stream["width"], stream["height"]) < 1280:
        raise ValueError(f"録画条件を満たしません: {video}: {stream}")
    return float(info["format"]["duration"]), stream


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deliverables", type=Path)
    parser.add_argument("work", type=Path)
    parser.add_argument("runs", nargs="+", type=Path)
    args = parser.parse_args()
    timeline = []
    videos = []
    offset = 0
    for index, run in enumerate(args.runs):
        log = (run / "xcodebuild.log").read_text(errors="replace")
        start = re.search(r"^ACAS_PL_START\|PL-\d+\|([\d.]+)", log, re.M)
        if not start:
            raise ValueError(f"ケース開始時刻がありません: {run}")
        recording = json.loads((run / "recording.json").read_text())
        source = run / "simulator.mp4"
        duration, stream = probe(source)
        trim = max(0, float(start[1]) - recording["startEpoch"] - 0.5)
        if trim >= duration:
            raise ValueError(f"ケース開始時刻が録画範囲外です: {run}")
        part = args.work / f"part-{index:02d}.mp4"
        end = re.search(r"^Test Suite 'Selected tests' (?:passed|failed) at ([\d :.-]+)\.$", log, re.M)
        if not end:
            raise ValueError(f"テスト終了時刻がありません: {run}")
        stop = min(duration, datetime.fromisoformat(end[1]).timestamp() - recording["startEpoch"])
        if stop <= trim:
            raise ValueError(f"テスト終了時刻が録画範囲外です: {run}")
        rotation = "transpose=cclock," if stream["height"] > stream["width"] else ""
        subprocess.run([
            "ffmpeg", "-v", "error", "-y", "-ss", f"{trim:.6f}", "-i", str(source),
            "-t", f"{stop - trim:.6f}",
            "-an", "-vf", rotation + "scale=1440:1080:force_original_aspect_ratio=decrease,"
            "pad=1440:1080:(ow-iw)/2:(oh-ih)/2,setsar=1,fps=24",
            "-c:v", "libx264", "-preset", "ultrafast", "-crf", "19", "-threads", "2", str(part),
        ], check=True)
        videos.append(part.resolve())
        timeline.append({"run": str(run.resolve()), "offset": offset, "trim": trim})
        offset += probe(part)[0]
    concat = args.work / "concat.txt"
    concat.write_text("\n".join("file '" + str(p).replace("'", "'\\''") + "'" for p in videos) + "\n")
    final = args.deliverables / "ACAS-PL.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "concat", "-safe", "0",
                    "-i", str(concat), "-c", "copy", "-movflags", "+faststart", str(final)], check=True)
    duration, stream = probe(final)
    (args.work / "timeline.json").write_text(json.dumps(timeline, indent=2) + "\n")
    print(f"{final}: H.264 {stream['width']}x{stream['height']}, {duration:.2f}秒")


if __name__ == "__main__":
    main()
