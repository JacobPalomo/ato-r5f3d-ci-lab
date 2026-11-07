import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from extract_r5f3f_report import parse_log, TRUE_FLAGS, FALSE_FLAGS


class ReportTest(unittest.TestCase):
    def valid(self):
        return {
            'phase': 'R5F-3F',
            'mode': 'RAILS_HTTP_IN_PROCESS_SYNTHETIC_CI',
            **{key: True for key in TRUE_FLAGS},
            **{key: False for key in FALSE_FLAGS},
            'synthetic_private_messages': 2,
            'unique_receipts': 2,
            'job_adapter': 'test',
        }

    def log(self, report):
        return 'R5F3F_RESULT_JSON=' + json.dumps(report) + '\n'

    def test_valid(self):
        self.assertTrue(parse_log(self.log(self.valid()))['passed'])

    def test_missing_marker(self):
        with self.assertRaises(ValueError):
            parse_log('PASS\n')

    def test_duplicate_marker(self):
        line = self.log(self.valid())
        with self.assertRaises(ValueError):
            parse_log(line + line)

    def test_wrong_phase(self):
        d = self.valid()
        d['phase'] = 'R5F-3E'
        with self.assertRaises(ValueError):
            parse_log(self.log(d))

    def test_false_positive(self):
        d = self.valid()
        d['whatsapp_provider_tested'] = True
        with self.assertRaises(ValueError):
            parse_log(self.log(d))

    def test_truthy_string_rejected(self):
        d = self.valid()
        d['passed'] = 'true'
        with self.assertRaises(ValueError):
            parse_log(self.log(d))

    def test_wrong_note_count(self):
        d = self.valid()
        d['synthetic_private_messages'] = 3
        with self.assertRaises(ValueError):
            parse_log(self.log(d))

    def test_report_public_route_cannot_be_true(self):
        d = self.valid()
        d['persistent_http_route_installed'] = True
        with self.assertRaises(ValueError):
            parse_log(self.log(d))


if __name__ == '__main__':
    unittest.main()
