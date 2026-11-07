#!/usr/bin/env python3
"""Strictly accept a single R5F-3F Rails in-process HTTP CI verdict."""
import argparse
import json
from pathlib import Path
import sys

PREFIX = 'R5F3F_RESULT_JSON='
TRUE_FLAGS = (
    'passed', 'rails_runtime', 'rails_http_route_runtime_injected',
    'chatwoot_message_builder_executed', 'http_unauthorized_rejected',
    'http_created_201', 'http_replay_same_message_id',
    'http_payload_conflict_rejected', 'http_concurrent_duplicate_suppressed',
    'http_stale_claim_rejected', 'http_human_takeover_rejected',
    'public_message_rejected',
)
FALSE_FLAGS = (
    'persistent_http_route_installed', 'sidekiq_executed',
    'whatsapp_provider_tested', 'actual_human_ui_guard_installed',
    'production_modified', 'public_demo_deployed',
)


def parse_log(log: str) -> dict:
    values = [line[len(PREFIX):] for line in log.splitlines() if line.startswith(PREFIX)]
    if len(values) != 1 or len(values[0]) > 16384:
        raise ValueError('expected exactly one bounded R5F3F result')
    report = json.loads(values[0])
    if not isinstance(report, dict):
        raise ValueError('report is not an object')
    if report.get('phase') != 'R5F-3F' or report.get('mode') != 'RAILS_HTTP_IN_PROCESS_SYNTHETIC_CI':
        raise ValueError('phase/mode mismatch')
    for key in TRUE_FLAGS:
        if report.get(key) is not True:
            raise ValueError(f'{key} must be true')
    for key in FALSE_FLAGS:
        if report.get(key) is not False:
            raise ValueError(f'{key} must be false')
    for key in ('synthetic_private_messages', 'unique_receipts'):
        if type(report.get(key)) is not int or report[key] != 2:
            raise ValueError(f'{key} must equal 2')
    if report.get('job_adapter') != 'test':
        raise ValueError('job_adapter must be test')
    return report


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    try:
        report = parse_log(args.input.read_text(encoding='utf-8', errors='replace'))
        with args.output.open('x', encoding='utf-8') as outfile:
            json.dump(report, outfile, indent=2, sort_keys=True)
            outfile.write('\n')
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print('R5F3F_REPORT_REJECTED:', exc, file=sys.stderr)
        return 1
    print('PASS R5F-3F CI REPORT VALIDATED')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
