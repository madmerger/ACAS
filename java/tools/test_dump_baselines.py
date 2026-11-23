import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

import dump_baselines


class DumpBaselinesTest(unittest.TestCase):
    def test_compiler_reads_copybooks_from_repository(self):
        name, spec = next(iter(dump_baselines.INDEXED.items()))
        with tempfile.TemporaryDirectory() as tmp, patch("dump_baselines.subprocess.run") as run:
            dump_baselines.build(Path(tmp), name, spec)
            command = run.call_args.args[0]
            includes = [arg for index, arg in enumerate(command) if index and command[index - 1] == "-I"]
            self.assertEqual(includes, [str(dump_baselines.REPO), str(dump_baselines.REPO / "copybooks")])
            self.assertEqual(run.call_args.kwargs["cwd"], dump_baselines.REPO)
            self.assertTrue((dump_baselines.REPO / spec[0]).is_file())
