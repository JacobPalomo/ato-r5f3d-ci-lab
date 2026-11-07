#!/usr/bin/env python3
"""Fail-closed R5F-3J-02 report; logs are synthetic-only evidence markers."""
import argparse
import json
from pathlib import Path
import sys

EXPECTED = {
    'R5F3J2_SETUP_JSON=': {'synthetic_whatsapp': True, 'isolated_ci': True, 'events': 3, 'meta_credentials': False},
    'R5F3J2_INITIAL_JSON=': {'authorized_201': True, 'replay_200': True, 'human_queued_201': True,
                              'conflict_409': True, 'unauthorized_401': True, 'unsupported_422': True},
    'R5F3J2_REVOKE_JSON=': {'changed_claim': True, 'human_took_over_before_worker': True},
    'R5F3J2_REVOKED_JSON=': {'stale_claim_409': True, 'human_takeover_409': True},
    'R5F3J2_REPLAY_JSON=': {'replay_job_queued': True},
    'R5F3J2_VERIFY_JSON=': {'native_messages_created': 2, 'sidekiq_attempts': 3,
        'provider_fake_receipts': 1, 'human_job_blocked': True,
        'no_duplicate_replay': True, 'no_real_meta': True, 'production_modified': False},
}

def parse_log(log: str) -> dict:
    evidence = {}
    for marker, expected in EXPECTED.items():
        lines = [line[len(marker):] for line in log.splitlines() if line.startswith(marker)]
        if len(lines) != 1 or len(lines[0]) > 2048:
            raise ValueError(f'expected one bounded {marker}')
        obj = json.loads(lines[0])
        if not isinstance(obj, dict) or set(obj) != set(expected):
            raise ValueError(f'unexpected evidence shape: {marker}')
        if any(type(obj[k]) is not type(v) or obj[k] != v for k, v in expected.items()):
            raise ValueError(f'failed evidence: {marker}')
        if set(evidence) & set(obj):
            raise ValueError('evidence key collision')
        evidence.update(obj)
    return {'phase': 'R5F-3J-02', 'mode': 'CI_ONLY_RAILS_NATIVE_HTTP_SIDEKIQ_FAKE_PROVIDER',
        'passed': True, **evidence,
        'real_n8n_connected': False, 'real_meta_delivery_tested': False,
        'native_human_ui_integrated': False, 'provider_lost_ack_recovery_proven': False,
        'cross_database_fencing_proven': False, 'production_modified': False,
        'note': 'Rails HTTP + native Chatwoot message + real Sidekiq isolated queue + in-process fake WhatsApp. No n8n integration, Meta, customer credentials or production deployment.'}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    try:
        result = parse_log(args.input.read_text(encoding='utf-8', errors='replace'))
        with args.output.open('x', encoding='utf-8') as f:
            json.dump(result, f, sort_keys=True, indent=2)
            f.write('\n')
    except (ValueError, OSError, json.JSONDecodeError) as exc:
        print('R5F3J2_REPORT_REJECTED:', exc, file=sys.stderr)
        return 1
    print('PASS R5F-3J-02 RAILS_HTTP_SIDEKIQ_FAKE_WHATSAPP_ISOLATED_CI')
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
