"""Regression guard for Chatwoot v4.19.0 WhatsApp contact source IDs."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
SETUP = (ROOT / "rails/r5f3i_setup.rb").read_text(encoding="utf-8")
PROVIDER = (ROOT / "rails/overlay/config/initializers/zz_ato_ci_r5f3i.rb").read_text(encoding="utf-8")


class TestWhatsAppSourceId(unittest.TestCase):
    def fixture_recipient(self):
        match = re.search(r"ContactInbox\.create!\([^\n]*source_id: '([^']+)'", SETUP)
        self.assertIsNotNone(match, "Missing synthetic WhatsApp contact source ID")
        return match.group(1)

    def test_follows_chatwoot_v419_whatsapp_source_id_format(self):
        recipient = self.fixture_recipient()
        self.assertRegex(recipient, r"\A(?:[0-9]{1,15}|[A-Z]{2}\.(?:ENT\.)?[A-Za-z0-9]{1,128})\Z")

    def test_fake_provider_expects_exactly_same_recipient(self):
        match = re.search(r"unless recipient == '([^']+)'", PROVIDER)
        self.assertIsNotNone(match, "Missing fake provider recipient gate")
        self.assertEqual(match.group(1), self.fixture_recipient())


if __name__ == "__main__":
    unittest.main()
