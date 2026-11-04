"""Run with: python3 -B -m unittest discover -s prototypes/cloudscape -p 'test_*.py'"""

import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("trial", Path(__file__).with_name("try-papertoy.py"))
trial = importlib.util.module_from_spec(spec)
spec.loader.exec_module(trial)


class TrialTests(unittest.TestCase):
    def test_shader_preserves_defaults_and_uses_live_uniform(self):
        source = trial.shader_source()
        self.assertIn("#define dark uDark", source)
        self.assertIn("#define time (iTime * 0.2)", source)
        self.assertIn("const float definition = 0.4;", source)
        self.assertIn("void mainImage", source)
        self.assertNotIn("gl_FragColor", source)
        self.assertNotIn("gl_FragCoord", source)

    def test_production_shader_matches_approved_prototype(self):
        production = Path(__file__).resolve().parents[2] / "home/damon/cloudscape/clouds.glsl"
        self.assertEqual(production.read_text().strip(), trial.shader_source().strip())

    def test_palette_publication_replaces_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "palette"
            trial.write_palette(path, "light")
            with path.open() as old:
                trial.write_palette(path, "dark")
                self.assertEqual(old.read(), "light\n")
            self.assertEqual(path.read_text(), "dark\n")
            self.assertFalse(path.with_suffix(".tmp").exists())

    def test_darkman_values_are_validated(self):
        with patch.object(trial, "run") as run:
            run.return_value = subprocess.CompletedProcess([], 0, stdout="dark\n")
            self.assertEqual(trial.read_darkman(), "dark")
            self.assertEqual(run.call_args.kwargs["timeout"], 2)
            run.return_value.stdout = "unknown"
            with self.assertRaises(ValueError):
                trial.read_darkman()


if __name__ == "__main__":
    unittest.main()
