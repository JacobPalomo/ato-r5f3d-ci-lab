#!/usr/bin/env python3
"""Strict R5F-3I evidence parser. No production claims, no raw provider data."""
import argparse
import json
from pathlib import Path
import sys

EXPECTED = {
    'R5F3I_SETUP_JSON=': {
        'synthetic_whatsapp_channel': True,
        'no_meta_credentials': True,
    },
    'R5F3I_ENQUEUE_JSON=': {
        'sidekiq_send_reply_jobs_queued': 2,
        'human_takeover_before_worker': True,
        'synthetic_public_outgoing_messages': 2,
    },
    'R5F3I_REQUEUE_JSON=': {'replay_job_queued': True},
    'R5F3I_VERIFY_JSON=': {
        'real_sidekiq_job_attempts': 3,
        'fake_whatsapp_provider_receipts': 1,
        'blocked_human_outbound_jobs': 1,
        'replay_without_new_fake_provider_receipt': True,
        'source_id_recorded': True,
        'no_meta_http_executed': True,
    },
}


def parse_log(value: str) -> dict:
    fields = {}
    for marker, expected in EXPECTED.items():
        lines = [line[len(marker):] for line in value.splitlines() if line.startswith(marker)]
        if len(lines) != 1 or len(lines[0]) > 8192:
            raise ValueError(f'exactly one bounded {marker} required')
        current = json.loads(lines[0])
        if not isinstance(current, dict) or set(current) != set(expected):
            raise ValueError(f'unexpected keys: {marker}')
        for key, target in expected.items():
            if type(current[key]) is not type(target) or current[key] != target:
                raise ValueError(f'criterion failed: {key}')
        if fields.keys() & current.keys():
            raise ValueError('duplicate evidence field')
        fields.update(current)
    return {
        'phase': 'R5F-3I',
        'mode': 'REAL_SIDEKIQ_FAKE_WHATSAPP_PROVIDER_EPHEMERAL_CI',
        'passed': True,
        **fields,
        'actual_send_reply_job_executed': True,
        'chatwoot_whatsapp_dispatch_path_exercised': True,
        'fake_sink_only': True,
        'real_meta_delivery_tested': False,
        'real_meta_idempotency_proven': False,
        'lost_provider_ack_recovery_proven': False,
        'human_ui_integrated': False,
        'production_modified': False,
        'public_demo_deployed': False,
        'note': 'Synthetic WhatsApp channel, real Sidekiq and Chatwoot dispatch until an in-process fake provider. No provider HTTP, no exactly-once Meta claim.',
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = parse_log(args.input.read_text(encoding='utf-8', errors='replace'))
        with args.output.open('x', encoding='utf-8') as f:
            json.dump(report, f, indent=2, sort_keys=True)
            f.write('\n')
    except (ValueError, json.JSONDecodeError, OSError) as error:
        print('R5F3I_REPORT_REJECTED:', error, file=sys.stderr)
        return 1
    print('PASS R5F-3I REAL_SIDEKIQ_FAKE_WHATSAPP_PROVIDER_EPHEMERAL_CI')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
