"""Reuse completed XCTest evidence for exactly the source being packaged."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import urllib.error
import urllib.request


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, file, code, message, headers, url):
        return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--runs', required=True)
    parser.add_argument('--external-failures', default='[]')
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--complete-ui-log', type=Path)
    args = parser.parse_args()
    assert re.fullmatch(r'[0-9a-f]{40}', args.source)
    assert subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip() == args.source, 'Checkout is not the validated application source'
    run_ids = [int(value) for value in args.runs.split(',')]
    assert run_ids and len(set(run_ids)) == len(run_ids)
    expected, test_identifiers = {}, {}
    for suite in ['HarborTests', 'HarborIntegrationTests', 'HarborUITests']:
        for path in (Path('ios') / suite).glob('*.swift'):
            source_text = path.read_text('utf-8')
            methods = re.findall(r'func (test\w+)\(', source_text)
            if not methods:
                continue
            classes = re.findall(r'class (\w+)\s*:\s*XCTestCase', source_text)
            assert len(classes) == 1, 'Each test file must identify its XCTestCase'
            for name in methods:
                assert name not in expected, 'Ambiguous test inventory'
                expected[name] = suite
                test_identifiers[name] = suite + '/' + classes[0] + '/' + name
    assert expected and all(suite in expected.values() for suite in ['HarborTests', 'HarborIntegrationTests', 'HarborUITests'])
    allowed = {(int(item['run']), item['test']): item['reason'] for item in json.loads(args.external_failures)}
    assert all(isinstance(reason, str) and reason.strip() for reason in allowed.values())
    repository = os.environ['GITHUB_REPOSITORY']
    headers = {'Accept': 'application/vnd.github+json', 'Authorization': 'Bearer ' + os.environ['GH_TOKEN'], 'User-Agent': 'Harbor-reviewed-validation'}
    api = 'https://api.github.com/repos/' + repository

    def get(path):
        with urllib.request.urlopen(urllib.request.Request(api + path, headers=headers), timeout=45) as response:
            return json.load(response)

    def log(job):
        request = urllib.request.Request(api + f'/actions/jobs/{job}/logs', headers=headers)
        try:
            response = urllib.request.build_opener(NoRedirect).open(request, timeout=45)
        except urllib.error.HTTPError as redirect:
            if redirect.code != 302:
                raise
            location = redirect.headers['Location']
            assert location.startswith('https://')
            # Repository credentials are never sent to the signed log URL.
            response = urllib.request.urlopen(location, timeout=60)
        with response:
            return response.read().decode('utf-8', errors='replace')

    observations, runs, steps, metrics = [], [], [], []

    def consume(text, run, job):
        assert not any(phrase in text for phrase in ['freed pointer', 'Restarting after unexpected exit']), 'Native runtime failure needs investigation'
        for match in re.finditer(r"Test Case '-\[([^ ]+) ([^\]]+)\]' (passed|failed|skipped) \(([^)]+)\)", text):
            full = match[1] + '/' + match[2]
            assert match[2] in expected, 'Unexpected test in evidence'
            item = {'run': run, 'job': job, 'name': full, 'method': match[2], 'result': match[3], 'duration': match[4]}
            if item['result'] == 'failed':
                key = (run, full)
                assert expected[item['method']] == 'HarborIntegrationTests' and key in allowed, 'Unresolved test failure: ' + full
                item['external_failure_review'] = allowed[key]
            observations.append(item)
        for value in re.findall(r'HARBOR_LIBRARY_PERFORMANCE (\{[^\r\n]+\})', text):
            metrics.append({'run': run, 'job': job, 'metrics': json.loads(value)})

    for run_id in run_ids:
        run = get(f'/actions/runs/{run_id}')
        assert run['status'] == 'completed' and run['head_sha'] == args.source, 'Evidence must be completed and from exactly this source'
        runs.append({key: run[key] for key in ['id', 'head_sha', 'conclusion', 'html_url', 'created_at']})
        for job in get(f'/actions/runs/{run_id}/jobs?per_page=100')['jobs']:
            assert job['status'] == 'completed'
            steps.extend({'run': run_id, 'name': step['name'], 'conclusion': step['conclusion']} for step in job['steps'])
            consume(log(job['id']), run_id, job['id'])
    if args.complete_ui_log:
        consume(args.complete_ui_log.read_text('utf-8'), int(os.environ['GITHUB_RUN_ID']), None)
    actual_failures = {(item['run'], item['name']) for item in observations if item['result'] == 'failed'}
    assert set(allowed) == actual_failures, 'External-failure review must exactly identify the observed failed service tests'
    approved = {}
    skip = 'testPictureInPictureStartsFromPausedVideoAndRestoresTheSameSession'
    for item in observations:
        if item['result'] == 'passed' or (item['method'] == skip and item['result'] == 'skipped'):
            approved.setdefault(item['method'], item)
        elif item['result'] == 'skipped':
            raise AssertionError('Unexpected skipped test: ' + item['name'])
    missing = sorted(set(expected) - set(approved))
    assert all(expected[name] == 'HarborUITests' for name in missing), 'Native/public coverage is incomplete'
    required = ['Parse Swift before building dependencies', 'Verify shared Rust on the Apple build host', 'Build and package Rust before Swift', 'Build simulator', 'Run bridge and model tests on iPhone simulator', 'Run real addon services on iPhone simulator']
    assert all(any(step['name'] == name and step['conclusion'] == 'success' for step in steps) for name in required), 'A required source-validation stage has no successful evidence'
    for item in metrics:
        assert item['metrics']['records'] == 250
        assert 0 < item['metrics']['snapshot_prepare_seconds'] < item['metrics']['build85_single_read_seconds']
        assert 0 < item['metrics']['optimized_100_reads_seconds'] < item['metrics']['build85_single_read_seconds'] / 5
    assert metrics and 'testLargeLibraryReadsAvoidTheBuild85DateSortingCost' in approved
    if args.complete_ui_log:
        assert not missing, 'Pending UI coverage did not complete'
    selection = [test_identifiers[name] for name in missing]
    value = {'application_source': args.source, 'workflow_source': os.environ.get('GITHUB_SHA'), 'reuse_authorized': True, 'complete': not missing, 'expected_inventory': expected, 'approved_results': approved, 'observations': observations, 'runs': runs, 'component_steps': steps, 'performance_observations': metrics, 'pending_ui': selection, 'external_failures_reviewed': [item for item in observations if item['result'] == 'failed']}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(value, indent=2) + '\n', 'utf-8')
    args.output.with_name('pending-ui-selection.txt').write_text('\n'.join(selection) + ('\n' if selection else ''), 'utf-8')
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write('needs_ui=' + str(bool(missing)).lower() + '\n')
    print(json.dumps({'source': args.source, 'approved': len(approved), 'pending_ui': selection, 'reviewed_external_failures': len(actual_failures)}))


if __name__ == '__main__':
    main()
