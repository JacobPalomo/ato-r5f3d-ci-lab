"""Local structural tests for the installed add-on; not a Rails runtime proof."""
from pathlib import Path
import subprocess
import unittest
ROOT=Path(__file__).resolve().parents[1]
class Tests(unittest.TestCase):
    def test_existing_smoke_kept(self):
        s=(ROOT/'scripts/run_r5f3d_ci.sh').read_text()
        self.assertIn('R5F3D_RAILS_BOOT_OK',s)
        self.assertLess(s.index('PHASE=RAILS_DB_SETUP'),s.index('PHASE=RAILS_BOOT'))
        self.assertIn('PHASE=R5F3E_REAL_MESSAGE_WRITE',s)
        self.assertIn('R5F3E_ENABLED:-false',s)
        self.assertEqual(subprocess.call(['bash','-n',str(ROOT/'scripts/run_r5f3d_ci.sh')]),0)
    def test_compose_isolated(self):
        c=(ROOT/'docker-compose.r5f3d.yaml').read_text()
        self.assertIn('r5f3e_write_test.rb:ro',c)
        self.assertIn('reports:/tmp/r5f3e_reports:rw',c)
        self.assertIn('internal: true',c)
        self.assertIn('R5F3E_ENABLED: ${R5F3E_ENABLED:-false}',c)
    def test_new_workflow_manual(self):
        w=(ROOT/'.github/workflows/r5f3e-functional.yml').read_text()
        self.assertIn('workflow_dispatch:',w)
        self.assertNotIn('push:',w)
        self.assertIn('ubuntu-24.04-arm',w)
        self.assertIn('contents: read',w)
        self.assertIn('persist-credentials: false',w)
    def test_ruby_syntax(self):
        out=subprocess.run(['ruby','-c',str(ROOT/'rails/r5f3e_write_test.rb')], capture_output=True, text=True)
        self.assertEqual(out.returncode,0,out.stderr)
    def test_no_real_provider(self):
        ruby=(ROOT/'rails/r5f3e_write_test.rb').read_text()
        self.assertIn('queue_adapter = :test',ruby)
        self.assertIn('Messages::MessageBuilder',ruby)
        self.assertIn('private: true',ruby)
        self.assertNotIn('http://',ruby)
        self.assertNotIn('https://',ruby)
if __name__=='__main__': unittest.main()
