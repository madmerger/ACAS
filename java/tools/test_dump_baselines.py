import tempfile
import unittest
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

import dump_baselines


class DumpBaselinesTest(unittest.TestCase):
    def test_unreadable_analysis_index_is_not_scanned_as_raw_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            evidence = root / "evidence"
            indexed = evidence / "baselines/sample/ledgers/acas/analysis.dat"
            indexed.parent.mkdir(parents=True)
            indexed.write_bytes(b"not a record boundary " + b"Saa000001" + b"Z" * 27)
            output = root / "output"
            with patch.object(dump_baselines.sys, "argv", ["dump_baselines.py", str(evidence), str(output)]), \
                 patch("dump_baselines.build", return_value=root / "dumper"), \
                 patch("dump_baselines.subprocess.run", return_value=CompletedProcess([], 1, "", "OPEN-ERROR:39")) as run:
                with self.assertRaisesRegex(SystemExit, "sample/acas/analysis.dat: 索引レコード境界を確認できません"):
                    dump_baselines.main()
                self.assertEqual(run.call_count, 2)
            self.assertFalse((output / "sample.json").exists())

    def test_compiler_reads_copybooks_from_repository(self):
        name, spec = next(iter(dump_baselines.INDEXED.items()))
        with tempfile.TemporaryDirectory() as tmp, patch("dump_baselines.subprocess.run") as run:
            dump_baselines.build(Path(tmp), name, spec)
            command = run.call_args.args[0]
            includes = [arg for index, arg in enumerate(command) if index and command[index - 1] == "-I"]
            self.assertEqual(includes, [str(dump_baselines.REPO), str(dump_baselines.REPO / "copybooks")])
            self.assertEqual(run.call_args.kwargs["cwd"], dump_baselines.REPO)
            self.assertTrue((dump_baselines.REPO / spec[0]).is_file())
