"""Run with a built native relay path; never touches a real Claude profile."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

BINARY = Path(sys.argv.pop(1)).resolve() if __name__ == '__main__' and len(sys.argv) > 1 and not sys.argv[1].startswith('-') else None


@unittest.skipUnless(BINARY and BINARY.is_file(), 'Pass the built native relay executable')
class StatusLineRelayTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="quota relay '-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.input = {'session_id': 'session-one', 'session_name': 'PRIVATE TITLE',
                      'access_token': 'SECRET MUST NOT BE COPIED',
                      'rate_limits': {'five_hour': {'used_percentage': 25, 'resets_at': 1893456000},
                                      'seven_day': {'used_percentage': 40, 'resets_at': 1893800000}}}

    def run_relay(self, identity='account-one', data=None):
        return subprocess.run([str(BINARY), '--root', str(self.root), '--identity', identity],
                              input=json.dumps(data or self.input), text=True, capture_output=True,
                              timeout=6, check=True)

    def test_filters_payload_and_creates_private_snapshot(self):
        result = self.run_relay()
        snapshot = self.root / 'quotamate/usage.json'
        data = json.loads(snapshot.read_text())
        self.assertEqual(set(data), {'identity', 'capturedAt', 'rate_limits'})
        self.assertEqual(data['rate_limits']['five_hour']['used_percentage'], 25)
        self.assertNotIn('PRIVATE', snapshot.read_text())
        self.assertNotIn('SECRET', snapshot.read_text())
        self.assertEqual(snapshot.stat().st_mode & 0o777, 0o600)
        self.assertIn('5h 25%', result.stdout)

    def test_old_session_cannot_overwrite_a_new_identity_binding(self):
        self.run_relay()
        snapshot = self.root / 'quotamate/usage.json'
        original = snapshot.read_text()
        self.run_relay('account-two')
        self.assertEqual(snapshot.read_text(), original)
        self.run_relay('account-two', {**self.input, 'session_id': 'new-session'})
        self.assertEqual(json.loads(snapshot.read_text())['identity'], 'account-two')

    def test_preserves_existing_status_line_output_even_when_it_ignores_input(self):
        private = self.root / 'quotamate'
        private.mkdir(mode=0o700)
        (private / 'original-statusline.json').write_text(json.dumps({'statusLine': {'command': 'printf original-output'}}))
        result = self.run_relay(data={**self.input, 'ignored': 'x' * 50000})
        self.assertEqual(result.stdout, 'original-output')

    def test_missing_usage_does_not_refresh_old_values(self):
        self.run_relay()
        snapshot = self.root / 'quotamate/usage.json'
        original = snapshot.read_text()
        self.run_relay(data={'session_id': 'session-one', 'model': {'display_name': 'Claude'}})
        self.assertEqual(snapshot.read_text(), original)


if __name__ == '__main__':
    unittest.main()
