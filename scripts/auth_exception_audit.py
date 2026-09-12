"""Read service journal locally; output only allowlisted exception categories."""
import collections
import json
import re
import subprocess

result = subprocess.run(
    ['journalctl', '-u', 'securewave-api.service', '--since', '24 hours ago',
     '--no-pager', '-o', 'cat'], capture_output=True, text=True, timeout=30,
)
allowed = {'ValueError', 'TypeError', 'AttributeError', 'UnknownHashError',
           'MissingBackendError', 'OperationalError', 'ProgrammingError',
           'InvalidTokenError', 'RuntimeError'}
counts = collections.Counter()
for name in re.findall(r'Login error exception_type=([A-Za-z]+)', result.stdout):
    counts[name if name in allowed else 'OtherException'] += 1
print(json.dumps({'journal_returncode': result.returncode,
                  'journal_has_entries': bool(result.stdout.strip()),
                  'login_exception_counts': dict(counts)}, sort_keys=True))
