import json
import plistlib
import tempfile
import unittest
from pathlib import Path

from record_equivalence import collect_reports, expected_reports


class ReportCollectionTests(unittest.TestCase):
    def test_requires_each_expected_report_from_the_built_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            run = root / "ACAS.xctestrun"
            run.write_bytes(plistlib.dumps({"ACASUITests": {
                "TestHostPath": "__TESTROOT__/runner", "TestBundlePath": "__TESTHOST__/tests",
            }}))
            fixtures = root / "runner/tests/fixtures"
            fixtures.mkdir(parents=True)
            for case, fixture in {
                "PL-221": {"reports": {}, "equivalence": {"reportDigests": {"ledger/prt-1": {}}}},
                "PL-413": {"reports": {"ledger/prt-1": "00"}},
                "PL-001": {"reports": {}, "equivalence": {"outOfScope": "未実施"}},
            }.items():
                (fixtures / f"{case}.json").write_text(json.dumps(fixture))
            expected = expected_reports(run, ["PL-001", "PL-221", "PL-413"])
            self.assertEqual(expected, {Path("PL-221/prt-1"), Path("PL-413/prt-1")})

            source = root / "source"
            output = root / "reports"
            self.assertEqual(collect_reports(source, output, expected), sorted(expected))
            (source / "PL-221").mkdir(parents=True)
            (source / "PL-221/prt-1").touch()
            self.assertEqual(collect_reports(source, output, expected), [Path("PL-413/prt-1")])
            self.assertEqual((output / "PL-221/prt-1").read_bytes(), b"")
