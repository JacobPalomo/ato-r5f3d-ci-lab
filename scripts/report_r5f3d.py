#!/usr/bin/env python3
"""Create a sanitized, machine-readable verdict for ephemeral CI."""
import argparse
import json
import os
from pathlib import Path
from datetime import datetime, timezone

p = argparse.ArgumentParser()
p.add_argument('--output', required=True)
a = p.parse_args()
code = int(os.getenv('R5F3D_EXIT', '99'))
phase = os.getenv('R5F3D_PHASE', 'UNKNOWN')
cleaned = os.getenv('R5F3D_CLEANUP') == 'true'
report = {
    'phase': 'R5F-3D',
    'mode': 'EPHEMERAL_ARM64_CI_RAILS_SMOKE',
    'timestamp_utc': datetime.now(timezone.utc).isoformat(),
    'passed': code == 0 and cleaned and phase == 'SMOKE_PASS',
    'exit_code': code,
    'last_step': phase,
    'image_id_verified': os.getenv('R5F3D_IMAGE') == 'true',
    'rails_executed': os.getenv('R5F3D_RAILS') == 'true',
    'database_schema_ready': os.getenv('R5F3D_SCHEMA') == 'true',
    'cleanup_completed': cleaned,
    'rails_patch_installed': False,
    'rspec_executed': False,
    'message_writes_tested': False,
    'sidekiq_tested': False,
    'whatsapp_provider_tested': False,
    'cross_database_atomicity_proven': False,
    'notes': 'Only ephemeral, synthetic DB; no customer credentials or production access.'
}
out = Path(a.output)
out.parent.mkdir(parents=True, exist_ok=True)
out.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
print('REPORT:', out, 'PASS' if report['passed'] else 'NOT_PASS', 'last_step=', phase)
