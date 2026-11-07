#!/usr/bin/env python3
"""Strictly extract synthetic Chatwoot R5F-3E verdict from Rails stdout in CI.
No Docker/Git/DB/network usage; fail-closed on missing/duplicate/invalid evidence.
"""
import argparse
import json
from pathlib import Path
import sys

PREFIX = 'R5F3E_RESULT_JSON='
EXPECTED_TRUE = (
    'passed', 'rails_runtime', 'chatwoot_message_builder_executed',
    'concurrent_duplicate_suppressed', 'payload_conflict_rejected',
    'replay_same_message_id', 'stale_claim_rejected',
)
EXPECTED_FALSE = (
    'actual_human_ui_guard_installed', 'rails_http_route_patched',
    'sidekiq_executed', 'whatsapp_provider_tested',
    'public_demo_deployed', 'production_modified',
)


def parse_log(log: str) -> dict:
    candidates = [line[len(PREFIX):] for line in log.splitlines() if line.startswith(PREFIX)]
    if len(candidates) != 1:
        raise ValueError(f'exactly one R5F3E_RESULT_JSON marker required; found {len(candidates)}')
    if len(candidates[0]) > 16384:
        raise ValueError('marker payload too large')
    result = json.loads(candidates[0])
    if not isinstance(result, dict):
        raise ValueError('report payload must be object')
    if result.get('phase') != 'R5F-3E' or result.get('mode') != 'REAL_CHATWOOT_MODEL_WRITE_CI_ONLY':
        raise ValueError('wrong phase or mode')
    for key in EXPECTED_TRUE:
        if result.get(key) is not True:
            raise ValueError(f'{key} must be true')
    for key in EXPECTED_FALSE:
        if result.get(key) is not False:
            raise ValueError(f'{key} must be false')
    if type(result.get('synthetic_private_messages')) is not int or result['synthetic_private_messages'] != 2:
        raise ValueError('expected exactly two synthetic private messages')
    if type(result.get('unique_receipts')) is not int or result['unique_receipts'] != 2:
        raise ValueError('expected exactly two unique receipts')
    if type(result.get('concurrent_workers')) is not int or result['concurrent_workers'] != 2:
        raise ValueError('expected two concurrent workers')
    if result.get('job_adapter') != 'test':
        raise ValueError('job adapter must be test')
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    args = ap.parse_args()
    try:
        data = parse_log(args.input.read_text(encoding='utf-8', errors='replace'))
        # x means no overwrite: never silently turn a prior verdict into a PASS.
        with args.output.open('x', encoding='utf-8') as file:
            json.dump(data, file, ensure_ascii=False, indent=2, sort_keys=True)
            file.write('\n')
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print('R5F3E_REPORT_REJECTED:', str(exc), file=sys.stderr)
        return 1
    print(f'PASS R5F-3E REPORT SAVED: {args.output}')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
