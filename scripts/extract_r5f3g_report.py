#!/usr/bin/env python3
"""Fail-closed parser of the multi-process R5F-3G Rails HTTP server verdict.

Only outputs synthetic, bounded booleans and counts. Never exposes request bodies.
"""
import argparse
import json
from pathlib import Path
import sys

REQUIRED = {
    'R5F3G_INITIAL_JSON=': {
        'unauthorized_401': True, 'created_201': True,
        'replay_200_same_id': True, 'conflict_409': True,
        'public_rejected_422': True, 'concurrency_one_write': True,
    },
    'R5F3G_REPLAY_JSON=': {'after_server_restart_replay_200': True},
    'R5F3G_TAKEOVER_JSON=': {'stale_rejected_409': True, 'human_rejected_409': True},
    'R5F3G_VERIFY_JSON=': {
        'database_receipts': 2, 'database_private_messages': 2,
        'human_takeover_simulated': True, 'no_public_message': True,
    },
}


def parse_log(value: str) -> dict:
    merged = {}
    for prefix, expected in REQUIRED.items():
        found = [line[len(prefix):] for line in value.splitlines() if line.startswith(prefix)]
        if len(found) != 1 or len(found[0]) > 8192:
            raise ValueError(f'exactly one bounded {prefix} marker required')
        obj = json.loads(found[0])
        if not isinstance(obj, dict) or set(obj) != set(expected):
            raise ValueError(f'unexpected keys for {prefix}')
        for key, wanted in expected.items():
            got = obj.get(key)
            if type(got) is not type(wanted) or got != wanted:
                raise ValueError(f'failed {key}')
        merged.update(obj)
    return {
        'phase': 'R5F-3G',
        'mode': 'REAL_HTTP_SEPARATE_RAILS_PROCESS_EPHEMERAL_CI',
        'passed': True,
        **merged,
        'route_persistent_across_server_restart': True,
        'production_route_installed': False,
        'real_human_ui_guard_installed': False,
        'sidekiq_executed': False,
        'whatsapp_provider_tested': False,
        'production_modified': False,
        'public_demo_deployed': False,
        'notes': 'Disposable Rails server over isolated Docker HTTP; synthetic Channel::Api private notes. Not production authorization or WhatsApp delivery.',
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    try:
        result = parse_log(args.input.read_text(encoding='utf-8', errors='replace'))
        with args.output.open('x', encoding='utf-8') as file:
            json.dump(result, file, indent=2, ensure_ascii=False, sort_keys=True)
            file.write('\n')
    except (OSError, ValueError, json.JSONDecodeError) as e:
        print('R5F3G_REPORT_REJECTED:', str(e), file=sys.stderr)
        return 1
    print('PASS R5F-3G REAL_HTTP_SEPARATE_RAILS_PROCESS_EPHEMERAL_CI')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
