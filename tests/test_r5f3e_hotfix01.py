import importlib.util
import json
from pathlib import Path
import unittest
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('ex', ROOT/'scripts/extract_r5f3e_report.py')
ex = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ex)


def valid():
    d = {key: True for key in ex.EXPECTED_TRUE}
    d.update({key: False for key in ex.EXPECTED_FALSE})
    d.update(phase='R5F-3E', mode='REAL_CHATWOOT_MODEL_WRITE_CI_ONLY',
             synthetic_private_messages=2, unique_receipts=2, concurrent_workers=2,
             job_adapter='test')
    return d


class TestHotfix(unittest.TestCase):
    def test_parse_valid_marker(self):
        d = valid()
        self.assertEqual(ex.parse_log('Rails logs\n'+ex.PREFIX+json.dumps(d)+'\nPASS\n'), d)

    def test_reject_missing_marker(self):
        with self.assertRaises(ValueError): ex.parse_log('PASS but missing evidence')

    def test_reject_duplicate_marker(self):
        s = ex.PREFIX+json.dumps(valid())+'\n'
        with self.assertRaises(ValueError): ex.parse_log(s+s)

    def test_reject_wrong_phase(self):
        d = valid(); d['phase'] = 'R5F-3D'
        with self.assertRaises(ValueError): ex.parse_log(ex.PREFIX+json.dumps(d))

    def test_reject_false_pass(self):
        d = valid(); d['passed'] = False
        with self.assertRaises(ValueError): ex.parse_log(ex.PREFIX+json.dumps(d))

    def test_reject_missing_receipts(self):
        d = valid(); d['unique_receipts'] = 1
        with self.assertRaises(ValueError): ex.parse_log(ex.PREFIX+json.dumps(d))

    def test_reject_sidekiq_claim(self):
        d = valid(); d['sidekiq_executed'] = True
        with self.assertRaises(ValueError): ex.parse_log(ex.PREFIX+json.dumps(d))

    def test_reject_bad_json(self):
        with self.assertRaises(json.JSONDecodeError): ex.parse_log(ex.PREFIX+'{')

    def test_script_still_guards_ci_and_reports(self):
        sh = (ROOT/'scripts/run_r5f3d_ci.sh').read_text()
        rb = (ROOT/'rails/r5f3e_write_test.rb').read_text()
        self.assertIn('R5F3E_RESULT_JSON=', rb)
        self.assertIn('extract_r5f3e_report.py', sh)
        self.assertIn('PHASE=R5F3E_REAL_MESSAGE_WRITE', sh)
        self.assertIn('GITHUB_ACTIONS', sh)
        self.assertNotIn('File.write(output', rb)

    def test_compose_mount_removed(self):
        y = (ROOT/'docker-compose.r5f3d.yaml').read_text()
        self.assertNotIn('reports:/tmp/r5f3e_reports', y)
        self.assertIn('networks: [isolated]', y)

    def test_local_x_write(self):
        with TemporaryDirectory() as tmp:
            target = Path(tmp)/'report.json'
            with target.open('x') as fp: fp.write('first')
            with self.assertRaises(FileExistsError): target.open('x')


if __name__ == '__main__':
    unittest.main()
