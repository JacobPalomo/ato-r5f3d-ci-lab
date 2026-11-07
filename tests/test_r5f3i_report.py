import importlib.util
import json
from pathlib import Path
import unittest

FILE = Path(__file__).resolve().parents[1] / 'scripts/extract_r5f3i_report.py'
spec = importlib.util.spec_from_file_location('extract_r5f3i_report', FILE)
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)


class ReportTest(unittest.TestCase):
    def sample(self):
        return '\n'.join(k + json.dumps(v) for k, v in parser.EXPECTED.items()) + '\n'

    def test_pass(self):
        result = parser.parse_log(self.sample())
        self.assertTrue(result['passed'])
        self.assertTrue(result['actual_send_reply_job_executed'])
        self.assertFalse(result['real_meta_idempotency_proven'])

    def test_missing(self):
        with self.assertRaises(ValueError):
            parser.parse_log('')

    def test_duplicate(self):
        with self.assertRaises(ValueError):
            parser.parse_log(self.sample() + self.sample())

    def test_missing_provider(self):
        with self.assertRaises(ValueError):
            parser.parse_log('\n'.join(x for x in self.sample().splitlines() if not x.startswith('R5F3I_VERIFY_JSON=')))

    def test_false_claim(self):
        text = self.sample().replace('"no_meta_http_executed": true', '"no_meta_http_executed": false')
        with self.assertRaises(ValueError):
            parser.parse_log(text)

    def test_invalid_count(self):
        text = self.sample().replace('"fake_whatsapp_provider_receipts": 1', '"fake_whatsapp_provider_receipts": 2')
        with self.assertRaises(ValueError):
            parser.parse_log(text)

    def test_bool_not_integer(self):
        text = self.sample().replace('"real_sidekiq_job_attempts": 3', '"real_sidekiq_job_attempts": true')
        with self.assertRaises(ValueError):
            parser.parse_log(text)

    def test_extra_field(self):
        text = self.sample().replace('"no_meta_credentials": true', '"no_meta_credentials": true, "unknown": true')
        with self.assertRaises(ValueError):
            parser.parse_log(text)

    def test_bad_json(self):
        text = self.sample().replace('{', '[', 1)
        with self.assertRaises(json.JSONDecodeError):
            parser.parse_log(text)

    def test_multiple_identical_field_names(self):
        original = parser.EXPECTED['R5F3I_SETUP_JSON='].copy()
        try:
            parser.EXPECTED['R5F3I_SETUP_JSON=']['replay_job_queued'] = True
            with self.assertRaises(ValueError):
                parser.parse_log(self.sample())
        finally:
            parser.EXPECTED['R5F3I_SETUP_JSON='] = original


if __name__ == '__main__':
    unittest.main()
