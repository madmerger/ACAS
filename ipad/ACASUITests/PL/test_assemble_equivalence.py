import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from datetime import datetime
from pathlib import Path

from assemble_equivalence import fallback_rotation, recording_video


class RecordingOrientationTests(unittest.TestCase):
    def test_video_must_resolve_inside_its_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory).resolve()
            run = root / "run"
            run.mkdir()
            video = run / "simulator.mp4"
            video.touch()
            self.assertEqual(recording_video(run), video)
            video.unlink()
            video.symlink_to(root / "outside.mp4")
            with self.assertRaisesRegex(ValueError, "試行フォルダー外"):
                recording_video(run)

    def test_portrait_recording_only_rotates_manually_without_display_metadata(self):
        portrait = {"width": 2064, "height": 2752}
        self.assertEqual(fallback_rotation(portrait), "transpose=cclock,")
        self.assertEqual(fallback_rotation({**portrait, "side_data_list": [{"rotation": 90}]}), "")

    @unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "ffmpeg / ffprobe がありません")
    def test_trim_keeps_timeline_when_no_source_frame_at_trim(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "run"
            run.mkdir()
            subprocess.run([
                "ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=size=1280x720:rate=1/3:duration=6",
                "-c:v", "libx264", "-threads", "2", str(run / "simulator.mp4"),
            ], check=True)
            (run / "recording.json").write_text('{"startEpoch": 0}')
            end = datetime.fromtimestamp(3.5)
            (run / "xcodebuild.log").write_text(
                f"ACAS_PL_START|PL-001|1.5\nTest Suite 'Selected tests' passed at {end}.\n")
            subprocess.run([sys.executable, str(Path(__file__).with_name("assemble_equivalence.py")),
                            str(root), str(root), str(run)], check=True, capture_output=True)
            timeline = json.loads((root / "timeline.json").read_text())
            self.assertEqual(timeline[0]["trim"], 1)
            info = json.loads(subprocess.check_output([
                "ffprobe", "-v", "error", "-show_entries", "stream=start_time,duration",
                "-of", "json", str(root / "part-00.mp4"),
            ]))["streams"][0]
            self.assertEqual(float(info["start_time"]), 0)
            self.assertAlmostEqual(float(info["duration"]), 2.5, delta=1 / 24)
