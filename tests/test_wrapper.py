import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class WrapperTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        self.state = self.home / '.gentle-ai/state.json'
        self.state.parent.mkdir()
        self.original = {'installed_agents': ['command-code', 'commandcode', 'pi'], 'other': 42}
        self.state.write_text(json.dumps(self.original))
        self.bin = self.home / 'companion'
        self.bin.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\nprintf called > "$HOME/called"\nexit "${STUB_EXIT:-0}"\n')
        self.bin.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), GENTLE_CC_BIN=str(self.bin),
                        GENTLE_AI_BIN=str(self.bin), STUB_EXIT='0')

    def run_wrapper(self, *args, **env):
        return subprocess.run(['/bin/bash', str(ROOT / 'gentle-cc'), *args],
                              env={**self.env, **env}, capture_output=True, text=True)

    def assert_result(self, result, code, stdout, stderr=''):
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (code, stdout, stderr))

    def test_normal_commands_preserve_other_fields_and_exit_status(self):
        for command in ('sync', 'install'):
            for code in (0, 7):
                with self.subTest(command=command, code=code):
                    self.state.write_text(json.dumps(self.original))
                    result = self.run_wrapper(command, '--preset', 'test', STUB_EXIT=str(code))
                    self.assert_result(result, code, f'{command}\n--agent\ncommand-code\n--preset\ntest\n')
                    self.assertEqual(json.loads(self.state.read_text()),
                                     {'installed_agents': ['pi'], 'other': 42})
                    self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_help_and_dry_run_do_not_write_state(self):
        for command in ('sync', 'install', 'sync-all'):
            for flag in ('--help', '-h', '--dry-run', '--dry-run=true'):
                with self.subTest(command=command, flag=flag):
                    before = self.state.stat()
                    lock = self.state.parent / 'gentle-cc.lock'
                    lock.mkdir()
                    self.addCleanup(lambda: lock.rmdir() if lock.exists() else None)
                    result = self.run_wrapper(command, flag)
                    expected = f'{command}\n--agent\ncommand-code\n{flag}\n'
                    if command == 'sync-all':
                        expected = (f'Official sync: pi\nsync\n--agent\npi\n{flag}\n'
                                    f'Companion sync: command-code\nsync\n--agent\ncommand-code\n{flag}\n')
                    self.assert_result(result, 0, expected)
                    self.assertTrue(lock.is_dir())
                    lock.rmdir()
                    self.assertEqual(self.state.read_text(), json.dumps(self.original))
                    self.assertEqual(self.state.stat().st_mtime_ns, before.st_mtime_ns)

    def test_missing_python_fails_before_companion(self):
        empty = self.home / 'empty'
        empty.mkdir()
        for command in ('sync', 'install', 'sync-all'):
            with self.subTest(command=command):
                result = self.run_wrapper(command, PATH=str(empty))
                self.assert_result(result, 1, '', 'gentle-cc: python3 required for shared-state cleanup\n')
                self.assertFalse((self.home / 'called').exists())
                self.assertEqual(json.loads(self.state.read_text()), self.original)
                self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_atomic_replacement_preserves_permissions_and_old_readers(self):
        self.state.chmod(0o600)
        with self.state.open() as old_reader:
            self.assert_result(self.run_wrapper('sync'), 0, 'sync\n--agent\ncommand-code\n')
            self.assertEqual(json.load(old_reader), self.original)
        self.assertEqual(self.state.stat().st_mode & 0o777, 0o600)
        self.assertEqual(sorted(p.name for p in self.state.parent.iterdir()), ['state.json'])

    def test_invalid_state_fails_without_running_companion(self):
        self.state.write_text('{broken')
        result = self.run_wrapper('sync')
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stdout, '')
        self.assertTrue(result.stderr.startswith('gentle-cc: cannot clean shared state: '))
        self.assertEqual(self.state.read_text(), '{broken')
        self.assertFalse((self.home / 'called').exists())

    def test_busy_lock_rejects_without_mutation(self):
        (self.state.parent / 'gentle-cc.lock').mkdir()
        result = self.run_wrapper('sync')
        self.assert_result(result, 1, '', 'gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions\n')
        self.assertFalse((self.home / 'called').exists())
        self.assertEqual(json.loads(self.state.read_text()), self.original)

    def test_dry_run_false_still_cleans(self):
        self.assert_result(self.run_wrapper('sync', '--dry-run=false'), 0,
                           'sync\n--agent\ncommand-code\n--dry-run=false\n')
        self.assertEqual(json.loads(self.state.read_text()), {'installed_agents': ['pi'], 'other': 42})

    def test_schema_rejection_and_sync_all_preflight(self):
        for content in ('[]', '{"installed_agents": null}', '{"installed_agents": [42]}'):
            self.state.write_text(content)
            result = self.run_wrapper('sync-all')
            error = ('state must be a JSON object' if content == '[]'
                     else 'installed_agents must be a list of strings')
            self.assert_result(result, 1, '', f'gentle-cc: cannot clean shared state: {error}\n')
            self.assertEqual(self.state.read_text(), content)
            self.assertFalse((self.home / 'called').exists())
            self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_lock_covers_official_and_companion_and_cleanup_failure(self):
        self.bin.write_text('#!/bin/sh\n'
                            'test -d "$HOME/.gentle-ai/gentle-cc.lock" || exit 99\n'
                            'printf "[]" > "$HOME/.gentle-ai/state.json"\n'
                            'exit 7\n')
        # Official failure retains the existing wrapper error; lock still released.
        self.assert_result(self.run_wrapper('sync-all'), 1, 'Official sync: pi\n',
                           'gentle-cc: official sync failed\n')
        self.state.write_text(json.dumps(self.original))
        self.assert_result(self.run_wrapper('sync'), 1, '',
                           'gentle-cc: cannot clean shared state: state must be a JSON object\n')
        self.assertEqual(self.state.read_text(), '[]')
        self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_informational_without_python_and_doctor_preserve_state(self):
        empty = self.home / 'empty'
        empty.mkdir()
        for command, args, expected in (
                ('sync', ['--help'], 'sync\n--agent\ncommand-code\n--help\n'),
                ('doctor', ['--verbose'], 'doctor\n--verbose\n')):
            self.assert_result(self.run_wrapper(command, *args, PATH=str(empty)), 0, expected)
            self.assertEqual(self.state.read_text(), json.dumps(self.original))
        self.assertIn('gentle-cc sync', self.run_wrapper('--help').stdout)

    def test_missing_state_is_not_created_by_cleanup(self):
        # A fresh HOME is supported even when the companion writes no state.
        self.state = self.home / 'fresh/.gentle-ai/state.json'
        fresh_home = self.state.parents[1]
        fresh_home.mkdir()
        self.assert_result(self.run_wrapper('install', HOME=str(fresh_home)), 0,
                           'install\n--agent\ncommand-code\n')
        self.assertFalse(self.state.exists())
        self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_sync_all_retains_official_then_companion_routing(self):
        result = self.run_wrapper('sync-all')
        self.assert_result(result, 0, 'Official sync: pi\nsync\n--agent\npi\nCompanion sync: command-code\nsync\n--agent\ncommand-code\n')
        self.assertEqual(json.loads(self.state.read_text()), {'installed_agents': ['pi'], 'other': 42})


if __name__ == '__main__':
    unittest.main()
