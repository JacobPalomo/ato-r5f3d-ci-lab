import pathlib
import subprocess
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
SH = (ROOT / 'scripts/run_r5f3d_ci.sh').read_text(encoding='utf-8')

class TestBootstrapOrder(unittest.TestCase):
    def test_prepare_before_first_rails_runner(self):
        self.assertLess(SH.index('PHASE=RAILS_DB_SETUP'), SH.index('PHASE=RAILS_BOOT'))
        self.assertLess(SH.index('db:chatwoot_prepare'), SH.index('R5F3D_RAILS_BOOT_OK'))

    def test_verifies_required_tables_before_marking_schema_ready(self):
        for name in ('installation_configs', 'messages', 'conversations', 'accounts'):
            self.assertIn("to_regclass('public.%s')" % name, SH)
        self.assertLess(SH.index('SCHEMA_INCOMPLETE'), SH.index('SCHEMA_READY=true', SH.index('PHASE=RAILS_DB_SETUP')))

    def test_preserves_isolation_and_cleanup(self):
        self.assertIn('trap finish EXIT', SH)
        self.assertIn('down -v --remove-orphans', SH)
        self.assertIn('EXPECTED_IMAGE=', SH)
        self.assertIn("RUNNER_ARCH:-}", SH)

    def test_bash_syntax(self):
        result = subprocess.run(['bash', '-n', str(ROOT/'scripts/run_r5f3d_ci.sh')], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
