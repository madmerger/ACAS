import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch


spec = importlib.util.spec_from_file_location(
    'runtimes', Path(__file__).with_name('check-runtimes.py'),
)
runtimes = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtimes)


class RuntimeTests(unittest.TestCase):
    def test_supported_and_newer_lts(self):
        releases = [
            dict(cycle='21', releaseDate='2023-09-19', eol='2029-12-31', lts=True),
            dict(cycle='25', releaseDate='2025-09-16', eol=False, lts=True),
        ]
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertFalse(runtimes.assess('eclipse-temurin', '21', releases, '2026-01-01'))
        self.assertIn('newer LTS 25', output.getvalue())

    def test_eol_and_unknown(self):
        releases = [dict(cycle='3.8', releaseDate='2019-10-14', eol='2024-10-07')]
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertTrue(runtimes.assess('python', '3.8', releases, '2026-01-01'))
            self.assertFalse(runtimes.assess('python', '3.99', releases, '2026-01-01'))
        self.assertIn('::error::', output.getvalue())
        self.assertIn('no lifecycle data', output.getvalue())

    def test_future_release_not_recommended(self):
        releases = [
            dict(cycle='21', releaseDate='2023-09-19', eol=False, lts=True),
            dict(cycle='25', releaseDate='2025-09-16', eol=False, lts=True),
        ]
        with contextlib.redirect_stdout(io.StringIO()) as output:
            runtimes.assess('eclipse-temurin', '21', releases, '2024-01-01')
        self.assertNotIn('::warning::', output.getvalue())

    def test_empty_root(self):
        with tempfile.TemporaryDirectory() as directory:
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(runtimes.declarations(Path(directory)), [])
        self.assertEqual(output.getvalue().count('SKIP'), 3)

    def test_extract_pom_and_workflow(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'java').mkdir()
            (root / '.github/workflows').mkdir(parents=True)
            (root / '.github/workflows/java.yml').write_text('java-version: "21"\n')
            (root / 'java/pom.xml').write_text(
                '<project xmlns="http://maven.apache.org/POM/4.0.0"><properties>'
                '<maven.compiler.release>17</maven.compiler.release>'
                '</properties></project>',
            )
            with contextlib.redirect_stdout(io.StringIO()):
                pins = runtimes.declarations(root)
        self.assertEqual(pins, [('eclipse-temurin', '17'), ('eclipse-temurin', '21')])

    def test_network_failure_warns(self):
        with patch('sys.argv', ['check-runtimes.py']), patch.object(
            runtimes, 'declarations', return_value=[('python', '3.12')],
        ), patch.object(runtimes.urllib.request, 'urlopen', side_effect=OSError('offline')):
            with contextlib.redirect_stdout(io.StringIO()) as output:
                self.assertEqual(runtimes.main(), 0)
        self.assertIn('lifecycle data unavailable: offline', output.getvalue())


if __name__ == '__main__':
    unittest.main()
