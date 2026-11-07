import importlib.util
import json
from pathlib import Path
import unittest

FILE = Path(__file__).resolve().parents[1] / 'scripts/extract_r5f3h_report.py'
spec = importlib.util.spec_from_file_location('extract_r5f3h_report', FILE)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class TestR5F3HReport(unittest.TestCase):
    def sample(self):
        return '\n'.join(p + json.dumps(obj) for p, obj in module.REQUIRED.items()) + '\n'

    def test_pass(self):
        data = module.parse_log(self.sample())
        self.assertTrue(data['passed'])
        self.assertFalse(data['browser_agent_ui_tested'])
        self.assertFalse(data['production_modified'])

    def test_missing(self):
        with self.assertRaises(ValueError):
            module.parse_log('')

    def test_duplicate(self):
        with self.assertRaises(ValueError):
            module.parse_log(self.sample() + self.sample())

    def test_missing_restart(self):
        lines = [l for l in self.sample().splitlines() if not l.startswith('R5F3H_RESTART_JSON=')]
        with self.assertRaises(ValueError):
            module.parse_log('\n'.join(lines))

    def test_false_flag(self):
        d = self.sample().replace('"native_agent_http_accepted": true', '"native_agent_http_accepted": false')
        with self.assertRaises(ValueError):
            module.parse_log(d)

    def test_wrong_count(self):
        d = self.sample().replace('"native_agent_messages": 2', '"native_agent_messages": 3')
        with self.assertRaises(ValueError):
            module.parse_log(d)

    def test_bool_number_confusion(self):
        d = self.sample().replace('"unique_receipts": 1', '"unique_receipts": true')
        with self.assertRaises(ValueError):
            module.parse_log(d)

    def test_extra_key(self):
        d = self.sample().replace('"guards_human": 2', '"guards_human": 2, "unexpected": true')
        with self.assertRaises(ValueError):
            module.parse_log(d)

    def test_malformed(self):
        with self.assertRaises(json.JSONDecodeError):
            module.parse_log(self.sample().replace('{', '[', 1))


if __name__ == '__main__':
    unittest.main()
