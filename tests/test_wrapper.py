import json
import os
from pathlib import Path
import subprocess
import signal
import time
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

    def test_agent_selectors_rejected_before_any_work(self):
        selectors = (
            ('--agent', 'pi'), ('--agent=pi',),
            ('--agent', 'command-code'), ('--agent=command-code',),
            ('--agent', ''), ('--agent=',), ('--agent',),
            ('--agent', 'command-code', '--agent', 'pi'),
            ('--agent=pi', '--agent=command-code'),
            ('--', '--agent', 'pi'), ('--', '--agent=pi'),
            ('--preset', '--agent=pi'),
        )
        error = ('gentle-cc: --agent is managed by the wrapper; '
                 'not allowed for sync, install, or sync-all\n')
        empty = self.home / 'empty'
        empty.mkdir()
        for command in ('sync', 'install', 'sync-all'):
            for selector in selectors:
                for prefix in ((), ('--help',), ('-h',), ('--dry-run',)):
                    for condition in ('normal', 'no-python', 'no-bin', 'busy',
                                      'invalid-state', 'missing-state'):
                        with self.subTest(command=command, selector=selector,
                                          prefix=prefix, condition=condition):
                            with tempfile.TemporaryDirectory() as home:
                                state = Path(home) / '.gentle-ai/state.json'
                                if condition != 'missing-state':
                                    state.parent.mkdir()
                                    state.write_bytes(b'{broken' if condition == 'invalid-state'
                                                      else self.state.read_bytes())
                                lock = state.parent / 'gentle-cc.lock'
                                if condition == 'busy':
                                    lock.mkdir()
                                before = state.read_bytes() if state.exists() else None
                                mtime = state.stat().st_mtime_ns if state.exists() else None
                                env = {'HOME': home, 'GENTLE_CC_REPO': str(Path(home) / 'no-repo')}
                                if condition == 'no-python':
                                    env['PATH'] = str(empty)
                                if condition == 'no-bin':
                                    env['GENTLE_CC_BIN'] = str(Path(home) / 'no-bin')
                                self.assert_result(self.run_wrapper(command, *prefix, *selector,
                                                                    **env), 1, '', error)
                                self.assertFalse((Path(home) / 'called').exists())
                                self.assertEqual(state.read_bytes() if state.exists() else None, before)
                                self.assertEqual(state.stat().st_mtime_ns if state.exists() else None,
                                                 mtime)
                                self.assertEqual(lock.exists(), condition == 'busy')
                                self.assertEqual(sorted(p.name for p in Path(home).iterdir()),
                                                 [] if condition == 'missing-state' else ['.gentle-ai'])
                                if state.parent.exists():
                                    self.assertEqual(sorted(p.name for p in state.parent.iterdir()),
                                                     ['gentle-cc.lock', 'state.json']
                                                     if condition == 'busy' else ['state.json'])

    def test_selector_text_inside_values_is_forwarded(self):
        # These tokens are not selector syntax; no external parser assumptions.
        flags = ('--preset=--agent', '--preset=--agent=pi', '--label', 'some--agent=pi')
        for command in ('sync', 'install', 'sync-all'):
            with self.subTest(command=command):
                self.state.write_text(json.dumps(self.original))
                self.assert_result(self.run_wrapper(command, *flags), 0,
                                   self.dry_run_stdout(command, flags))
                self.assertEqual(json.loads(self.state.read_text()),
                                 {'installed_agents': ['pi'], 'other': 42})

    def test_doctor_selector_and_build_and_help_routes_unchanged(self):
        before = self.state.read_bytes(), self.state.stat().st_mtime_ns
        self.assert_result(self.run_wrapper('doctor', '--agent', 'pi', '--agent='), 0,
                           'doctor\n--agent\npi\n--agent=\n')
        tools = self.home / 'tools'
        tools.mkdir()
        go = tools / 'go'
        go.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        go.chmod(0o755)
        repo = self.home / 'repo'
        repo.mkdir()
        self.assert_result(self.run_wrapper('build', '--agent=pi', PATH=str(tools),
                                            GENTLE_CC_REPO=str(repo)), 0,
                           f'Building companion from {repo} ...\nbuild\n-o\n{self.bin}\n'
                           f'./cmd/gentle-ai\nBuilt {self.bin}\n')
        for command in ('help', '--help', '-h'):
            result = self.run_wrapper(command, '--agent=pi')
            self.assertEqual((result.returncode, result.stderr), (0, ''))
            self.assertIn('gentle-cc sync', result.stdout)
        self.assertEqual((self.state.read_bytes(), self.state.stat().st_mtime_ns), before)
        self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_normal_commands_preserve_other_fields_and_exit_status(self):
        for command in ('sync', 'install'):
            for code in (0, 7):
                with self.subTest(command=command, code=code):
                    self.state.write_text(json.dumps(self.original))
                    result = self.run_wrapper(command, '--preset', 'test', STUB_EXIT=str(code))
                    self.assert_result(result, code, f'{command}\n--agent\ncommand-code\n--preset\ntest\n')
                    self.assertEqual(json.loads(self.state.read_text()),
                                     {'installed_agents': ['pi'], 'other': 42})
                    self.assertTrue((self.state.parent / 'gentle-cc.lock').is_file())

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
        self.assertEqual(sorted(p.name for p in self.state.parent.iterdir()),
                         ['gentle-cc.lock', 'state.json'])

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

    def dry_run_stdout(self, command, flags):
        suffix = ''.join(f'{flag}\n' for flag in flags)
        if command == 'sync-all':
            return (f'Official sync: pi\nsync\n--agent\npi\n{suffix}'
                    f'Companion sync: command-code\nsync\n--agent\ncommand-code\n{suffix}')
        return f'{command}\n--agent\ncommand-code\n{suffix}'

    def test_repeated_dry_run_effective_false_requires_preflight_lock_and_cleanup(self):
        empty = self.home / 'empty'
        empty.mkdir()
        flag_pairs = [('--dry-run', '--dry-run=false')]
        flag_pairs += [('--dry-run=true', f'--dry-run={value}')
                       for value in ('false', '0', 'f', 'F', 'FALSE', 'False')]
        for command in ('sync', 'install', 'sync-all'):
            for flags in flag_pairs:
                with self.subTest(command=command, flags=flags), tempfile.TemporaryDirectory() as home:
                    state = Path(home) / '.gentle-ai/state.json'
                    state.parent.mkdir()
                    state.write_text(json.dumps(self.original))
                    before = state.stat().st_mtime_ns
                    called = Path(home) / 'called'
                    lock = state.parent / 'gentle-cc.lock'
                    self.assert_result(self.run_wrapper(command, *flags, HOME=home, PATH=str(empty)),
                                       1, '', 'gentle-cc: python3 required for shared-state cleanup\n')
                    self.assertFalse(called.exists())
                    self.assertFalse(lock.exists())
                    self.assertEqual(state.read_text(), json.dumps(self.original))
                    self.assertEqual(state.stat().st_mtime_ns, before)
                    lock.mkdir()
                    self.assert_result(self.run_wrapper(command, *flags, HOME=home), 1, '',
                                       'gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions\n')
                    self.assertFalse(called.exists())
                    self.assertTrue(lock.is_dir())
                    self.assertEqual(state.read_text(), json.dumps(self.original))
                    self.assertEqual(state.stat().st_mtime_ns, before)
                    lock.rmdir()
                    self.assert_result(self.run_wrapper(command, *flags, HOME=home), 0,
                                       self.dry_run_stdout(command, flags))
                    self.assertTrue(called.exists())
                    self.assertEqual(json.loads(state.read_text()), {'installed_agents': ['pi'], 'other': 42})
                    self.assertTrue(lock.is_file())

    def test_repeated_dry_run_effective_true_and_help_do_not_mutate(self):
        flag_pairs = [('--dry-run=false', '--dry-run')]
        flag_pairs += [('--dry-run=false', f'--dry-run={value}')
                       for value in ('true', '1', 't', 'T', 'TRUE', 'True')]
        flag_pairs += [(help_flag, '--dry-run=true', '--dry-run=false')
                       for help_flag in ('--help', '-h')]
        lock = self.state.parent / 'gentle-cc.lock'
        lock.mkdir()
        before = self.state.stat().st_mtime_ns
        for command in ('sync', 'install', 'sync-all'):
            for flags in flag_pairs:
                with self.subTest(command=command, flags=flags):
                    self.assert_result(self.run_wrapper(command, *flags), 0,
                                       self.dry_run_stdout(command, flags))
                    self.assertEqual(self.state.read_text(), json.dumps(self.original))
                    self.assertEqual(self.state.stat().st_mtime_ns, before)
                    self.assertTrue(lock.is_dir())

    def test_schema_rejection_and_sync_all_preflight(self):
        for content in ('[]', '{"installed_agents": null}', '{"installed_agents": [42]}'):
            self.state.write_text(content)
            result = self.run_wrapper('sync-all')
            error = ('state must be a JSON object' if content == '[]'
                     else 'installed_agents must be a list of strings')
            self.assert_result(result, 1, '', f'gentle-cc: cannot clean shared state: {error}\n')
            self.assertEqual(self.state.read_text(), content)
            self.assertFalse((self.home / 'called').exists())
            self.assertTrue((self.state.parent / 'gentle-cc.lock').is_file())

    def test_lock_covers_official_and_companion_and_cleanup_failure(self):
        self.bin.write_text('#!/bin/sh\n'
                            'test -f "$HOME/.gentle-ai/gentle-cc.lock" || exit 99\n'
                            'printf "[]" > "$HOME/.gentle-ai/state.json"\n'
                            'exit 7\n')
        # Official failure retains the existing wrapper error; lock still released.
        self.assert_result(self.run_wrapper('sync-all'), 1, 'Official sync: pi\n',
                           'gentle-cc: official sync failed\n')
        self.state.write_text(json.dumps(self.original))
        self.assert_result(self.run_wrapper('sync'), 1, '',
                           'gentle-cc: cannot clean shared state: state must be a JSON object\n')
        self.assertEqual(self.state.read_text(), '[]')
        self.assertTrue((self.state.parent / 'gentle-cc.lock').is_file())

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
        self.assertTrue((self.state.parent / 'gentle-cc.lock').is_file())

    def wait_for(self, predicate):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if predicate():
                return
            time.sleep(0.02)
        self.fail('timed out waiting for fixture process')

    def test_os_lock_survives_wrapper_sigkill_until_live_child_exits(self):
        self.bin.write_text('#!/bin/sh\n'
                            'printf started > "$HOME/started"\n'
                            'while [ ! -f "$HOME/release" ]; do sleep 0.02; done\n')
        before = self.state.read_bytes(), self.state.stat().st_mtime_ns
        owner = subprocess.Popen(['/bin/bash', str(ROOT / 'gentle-cc'), 'sync-all'],
                                 env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True)
        try:
            self.wait_for(lambda: (self.home / 'started').exists())
            lock = self.state.parent / 'gentle-cc.lock'
            self.assertTrue(lock.is_file())
            inode = lock.stat().st_ino
            for killed in (False, True):
                if killed:
                    owner.kill()
                    owner.wait(timeout=5)
                self.assert_result(self.run_wrapper('install'), 1, '',
                                   'gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions\n')
                self.assertEqual((self.state.read_bytes(), self.state.stat().st_mtime_ns), before)
                self.assertEqual(lock.stat().st_ino, inode)
            (self.home / 'release').touch()
            stdout, stderr = owner.communicate(timeout=5)
            self.assertEqual((owner.returncode, stdout, stderr),
                             (-signal.SIGKILL, 'Official sync: pi\nCompanion sync: command-code\n', ''))
            self.assert_result(self.run_wrapper('sync'), 0, '')
            self.assertEqual(lock.stat().st_ino, inode)
            self.assertEqual(json.loads(self.state.read_text()), {'installed_agents': ['pi'], 'other': 42})
        finally:
            (self.home / 'release').touch()
            if owner.poll() is None:
                owner.kill()
            owner.communicate(timeout=5)

    def test_term_keeps_lock_until_signal_ignoring_child_finishes(self):
        self.bin.write_text('#!/bin/sh\ntrap "" TERM\n'
                            'printf started > "$HOME/started"\n'
                            'while [ ! -f "$HOME/release" ]; do sleep 0.02; done\n')
        before = self.state.read_bytes(), self.state.stat().st_mtime_ns
        owner = subprocess.Popen(['/bin/bash', str(ROOT / 'gentle-cc'), 'sync'],
                                 env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                 text=True)
        try:
            self.wait_for(lambda: (self.home / 'started').exists())
            owner.terminate()
            self.assertEqual(owner.wait(timeout=5), 143)
            self.assert_result(self.run_wrapper('sync'), 1, '',
                               'gentle-cc: shared state busy (gentle-cc.lock); see README recovery instructions\n')
            self.assertEqual((self.state.read_bytes(), self.state.stat().st_mtime_ns), before)
            (self.home / 'release').touch()
            self.assertEqual(owner.communicate(timeout=5), ('', ''))
            self.assert_result(self.run_wrapper('sync'), 0, '')
        finally:
            (self.home / 'release').touch()
            if owner.poll() is None:
                owner.kill()
            owner.communicate(timeout=5)

    def test_lock_backend_unavailable_fails_closed(self):
        # Shadow only the Python module, not any user installation.
        (self.home / 'sitecustomize.py').write_text(
            'import builtins\n'
            'original_import = builtins.__import__\n'
            'def fixture_import(name, *args, **kwargs):\n'
            '    if name == "fcntl": raise ImportError("fixture unavailable")\n'
            '    return original_import(name, *args, **kwargs)\n'
            'builtins.__import__ = fixture_import\n')
        before = self.state.read_bytes(), self.state.stat().st_mtime_ns
        self.assert_result(self.run_wrapper('sync', PYTHONPATH=str(self.home)), 1, '',
                           'gentle-cc: OS locking unavailable; requires Python 3 fcntl.flock on Linux/macOS\n')
        self.assertEqual((self.state.read_bytes(), self.state.stat().st_mtime_ns), before)
        self.assertFalse((self.home / 'called').exists())
        self.assertFalse((self.state.parent / 'gentle-cc.lock').exists())

    def test_sync_all_retains_official_then_companion_routing(self):
        result = self.run_wrapper('sync-all')
        self.assert_result(result, 0, 'Official sync: pi\nsync\n--agent\npi\nCompanion sync: command-code\nsync\n--agent\ncommand-code\n')
        self.assertEqual(json.loads(self.state.read_text()), {'installed_agents': ['pi'], 'other': 42})


if __name__ == '__main__':
    unittest.main()
