import unittest

from assemble_equivalence import fallback_rotation


class RecordingOrientationTests(unittest.TestCase):
    def test_portrait_recording_only_rotates_manually_without_display_metadata(self):
        portrait = {"width": 2064, "height": 2752}
        self.assertEqual(fallback_rotation(portrait), "transpose=cclock,")
        self.assertEqual(fallback_rotation({**portrait, "side_data_list": [{"rotation": 90}]}), "")
