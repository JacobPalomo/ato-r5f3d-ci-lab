import importlib.util
import json
from pathlib import Path
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts' / 'extract_r5f3g_report.py'
spec = importlib.util.spec_from_file_location('extract_r5f3g_report', SCRIPT)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class ReportTest(unittest.TestCase):
    def sample(self):
        return '\n'.join(prefix + json.dumps(obj) for prefix, obj in mod.REQUIRED.items()) + '\n'

    def test_valid(self):
        result = mod.parse_log(self.sample())
        self.assertTrue(result['passed'])
        self.assertFalse(result['production_route_installed'])
        self.assertTrue(result['route_persistent_across_server_restart'])

    def test_missing(self):
        with self.assertRaises(ValueError):
            mod.parse_log('')

    def test_duplicate(self):
        s = self.sample()
        with self.assertRaises(ValueError):
            mod.parse_log(s + s)

    def test_false_flag(self):
        s = self.sample().replace('"unauthorized_401": true', '"unauthorized_401": false')
        with self.assertRaises(ValueError):
            mod.parse_log(s)

    def test_malformed(self):
        s = self.sample().replace('{', '[', 1)
        with self.assertRaises(ValueError):
            mod.parse_log(s)

    def test_extra_key(self):
        s = self.sample().replace('"unauthorized_401": true', '"unauthorized_401": true, "fake": true')
        with self.assertRaises(ValueError):
            mod.parse_log(s)

    def test_int_boolean_confusion(self):
        s = self.sample().replace('"database_receipts": 2', '"database_receipts": true')
        with self.assertRaises(ValueError):
            mod.parse_log(s)

    def test_missing_replay(self):
        s = self.sample()
        with self.assertRaises(ValueError):
            mod.parse_log('\n'.join(x for x in s.splitlines() if not x.startswith('R5F3G_REPLAY_JSON=')))


if __name__ == '__main__':
    unittest.main()
