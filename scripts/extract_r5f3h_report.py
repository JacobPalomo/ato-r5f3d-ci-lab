#!/usr/bin/env python3
"""Fail-closed R5F-3H CI verdict: native authenticated agent API + DB guard."""
import argparse
import json
from pathlib import Path
import sys

REQUIRED = {
    'R5F3H_INITIAL_JSON=': {
        'native_agent_http_accepted': True,
        'bot_before_human_201': True,
        'bot_after_human_stale_409': True,
        'current_epoch_human_409': True,
        'human_first_blocks_bot_409': True,
    },
    'R5F3H_RESTART_JSON=': {'after_restart_bot_rejected': True},
    'R5F3H_VERIFY_JSON=': {
        'native_agent_messages': 2,
        'bot_private_notes': 1,
        'unique_receipts': 1,
        'guards_human': 2,
        'no_bot_after_takeover': True,
    },
}


def parse_log(log: str) -> dict:
    evidence = {}
    for prefix, template in REQUIRED.items():
        candidates = [line[len(prefix):] for line in log.splitlines() if line.startswith(prefix)]
        if len(candidates) != 1 or len(candidates[0]) > 4096:
            raise ValueError(f'one bounded marker required: {prefix}')
        obj = json.loads(candidates[0])
        if not isinstance(obj, dict) or set(obj) != set(template):
            raise ValueError(f'unexpected fields: {prefix}')
        for key, expected in template.items():
            observed = obj[key]
            if type(observed) is not type(expected) or observed != expected:
                raise ValueError(f'failed criterion: {key}')
        evidence.update(obj)
    return {
        'phase': 'R5F-3H',
        'mode': 'NATIVE_AUTHENTICATED_AGENT_API_ISOLATED_CI',
        'passed': True,
        **evidence,
        'rails_native_message_builder_hook_tested': True,
        'browser_agent_ui_tested': False,
        'all_human_paths_covered': False,
        'sidekiq_executed': False,
        'whatsapp_provider_tested': False,
        'production_modified': False,
        'public_demo_deployed': False,
        'note': 'Native Chatwoot authenticated agent message POST, not browser UI. CI-only hooks, no provider.',
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--input', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    a = ap.parse_args()
    try:
        data = parse_log(a.input.read_text(encoding='utf-8', errors='replace'))
        with a.output.open('x', encoding='utf-8') as f:
            json.dump(data, f, indent=2, sort_keys=True, ensure_ascii=False)
            f.write('\n')
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print('R5F3H_REPORT_REJECTED:', str(error), file=sys.stderr)
        return 1
    print('PASS R5F-3H NATIVE_AUTHENTICATED_AGENT_API_ISOLATED_CI')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
