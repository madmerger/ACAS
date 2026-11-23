import tempfile
import unittest
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
