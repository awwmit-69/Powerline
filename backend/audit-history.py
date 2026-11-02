"""Screen every reachable Git blob without printing credential values.

This is a targeted automated scan, not proof that a repository is secret-free.
Run in a full-history checkout, not a shallow clone.
"""
import re
import subprocess
import sys


def git(*args):
    return subprocess.check_output(['git', *args])


if git('rev-parse', '--is-shallow-repository').strip() != b'false':
    sys.exit('Full history is required for credential screening.')

rules = {
    'github-token': re.compile(rb'\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
    'stripe-secret': re.compile(rb'\bsk_(?:live|test)_[A-Za-z0-9]{16,}'),
    'aws-access-key': re.compile(rb'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b'),
    'private-key': re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'google-api-key': re.compile(rb'\bAIza[0-9A-Za-z_-]{35}\b'),
    'hardcoded-secret': re.compile(rb'''(?i)(?:api_?key|api_?secret|auth_?token|password|client_?secret)["']?\s*[:=]\s*["']([a-z0-9_./+\-=]{20,})["']'''),
}
placeholders = re.compile(rb'(?i)example|placeholder|your_|test[-_]|^x+$|process\.env|context\.|environment|secret_name')
objects = git('rev-list', '--objects', '--all').decode().splitlines()
scanned = 0
skipped = 0
findings = []
for entry in objects:
    oid, _, path = entry.partition(' ')
    if git('cat-file', '-t', oid).strip() != b'blob':
        continue
    if int(git('cat-file', '-s', oid)) > 5_000_000:
        skipped += 1
        continue
    content = git('cat-file', 'blob', oid)
    if b'\0' in content:
        skipped += 1
        continue
    scanned += 1
    for rule, pattern in rules.items():
        for match in pattern.finditer(content):
            if rule == 'hardcoded-secret' and placeholders.search(match.group(1)):
                continue
            line = content.count(b'\n', 0, match.start()) + 1
            findings.append((oid, path, line, rule))

print(f'Reachable text blobs screened: {scanned}; binary/large blobs skipped: {skipped}')
print('Scope: selected credential patterns across all fetched branches and tags.')
for oid, path, line, rule in findings:
    print(f'REVIEW {rule}: blob {oid}, path {path!r}, line {line}; value withheld')
print(f'Findings requiring review: {len(findings)}')
sys.exit(1 if findings else 0)
