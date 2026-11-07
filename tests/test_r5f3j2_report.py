import importlib.util
import json
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
parser_path = ROOT / 'scripts/extract_r5f3j2_report.py'
spec = importlib.util.spec_from_file_location('r5f3j2_report', parser_path)
parser = importlib.util.module_from_spec(spec)
spec.loader.exec_module(parser)

class ReportTests(unittest.TestCase):
    @staticmethod
    def valid():
        return '\n'.join(key + json.dumps(data) for key, data in parser.EXPECTED.items()) + '\n'

    def test_pass(self):
        self.assertTrue(parser.parse_log(self.valid())['passed'])

    def test_no_n8n_claim(self):
        self.assertFalse(parser.parse_log(self.valid())['real_n8n_connected'])

    def test_meta_not_claimed(self):
        self.assertFalse(parser.parse_log(self.valid())['real_meta_delivery_tested'])

    def test_missing(self):
        with self.assertRaises(ValueError): parser.parse_log('')

    def test_duplicate(self):
        with self.assertRaises(ValueError): parser.parse_log(self.valid() + self.valid())

    def test_wrong_boolean(self):
        bad = self.valid().replace('"authorized_201": true', '"authorized_201": false')
        with self.assertRaises(ValueError): parser.parse_log(bad)

    def test_bool_as_number(self):
        bad = self.valid().replace('"native_messages_created": 2', '"native_messages_created": true')
        with self.assertRaises(ValueError): parser.parse_log(bad)

    def test_wrong_count(self):
        bad = self.valid().replace('"sidekiq_attempts": 3', '"sidekiq_attempts": 2')
        with self.assertRaises(ValueError): parser.parse_log(bad)

    def test_extra_key(self):
        bad = self.valid().replace('"no_real_meta": true', '"no_real_meta": true, "unknown": true')
        with self.assertRaises(ValueError): parser.parse_log(bad)

    def test_missing_revoke(self):
        bad = '\n'.join(line for line in self.valid().splitlines() if not line.startswith('R5F3J2_REVOKED_JSON='))
        with self.assertRaises(ValueError): parser.parse_log(bad)

    def test_invalid_json(self):
        with self.assertRaises(json.JSONDecodeError): parser.parse_log(self.valid().replace('{', '[', 1))

    def test_bool_false_is_required(self):
        bad = self.valid().replace('"production_modified": false', '"production_modified": true')
        with self.assertRaises(ValueError): parser.parse_log(bad)

class SourceGuards(unittest.TestCase):
    def test_fake_provider_never_super(self):
        txt = (ROOT/'rails/overlay/config/initializers/zz_ato_ci_r5f3j2_worker.rb').read_text()
        segment = txt.split('module AtoCiR5f3j2FakeProvider',1)[1].split('Rails.application',1)[0]
        self.assertNotIn('super', segment)
        self.assertNotIn('HTTParty', segment)

    def test_single_queue(self):
        # The installer stays outside the repo. Audit the generated Compose instead.
        compose = (ROOT / 'docker-compose.r5f3d.yaml').read_text(encoding='utf-8')
        worker = compose.split('\n  r5f3j2-worker:\n', 1)[1].split('\nnetworks:\n', 1)[0]
        self.assertEqual(
            worker.count('command: ["bundle", "exec", "sidekiq", "-q", "ato_ci_r5f3j2", "-c", "1"]'),
            1,
        )
        self.assertIn('networks: [isolated]', worker)
        self.assertNotIn('\n    ports:', worker)

    def test_controller_validates_claim_before_receipt(self):
        txt = (ROOT/'rails/overlay/app/controllers/ato_ci_r5f3j2_outbound_controller.rb').read_text()
        self.assertLess(txt.index('stale_claim'),txt.index('AtoCiR5f3j2Receipt.find_by'))

    def test_no_staging_operational_mounts(self):
        # Verify the deployed CI services, not the external, uncommitted installer.
        compose = (ROOT / 'docker-compose.r5f3d.yaml').read_text(encoding='utf-8')
        services = compose.split('\n  r5f3j2-server:\n', 1)[1].split('\nnetworks:\n', 1)[0]
        self.assertIn('\n  r5f3j2-worker:\n', services)
        for forbidden in ('ATO_v0.6_Fase3', '/Users/', 'ato-chatwoot-n8n-lab', '\n    ports:'):
            self.assertNotIn(forbidden, services)
        self.assertEqual(services.count('networks: [isolated]'), 2)

if __name__ == '__main__': unittest.main()
