"""CLI process contracts. All scans/content reads/writes use temporary synthetic data."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import selectors
import signal
import stat
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[2]
CLI = ROOT / '.build/debug/disk-atlas'


class CLIBehaviorTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='atlas-cli-test-')
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.environment = dict(os.environ, LLVM_PROFILE_FILE=str(self.directory / 'profile-%p.profraw'))
        self.input = self.directory / 'input with spaces'
        self.input.mkdir()
        (self.input / 'a.txt').write_bytes(b'first duplicate\n' * 200)
        (self.input / 'b.txt').write_bytes((self.input / 'a.txt').read_bytes())
        (self.input / 'z.txt').write_bytes(b'different')
        self.snapshot = self.directory / 'scan.atlas'

    def call(self, *args, code=0, cwd=None):
        result = subprocess.run([str(CLI), *map(str, args)], cwd=cwd or self.directory,
                                text=True, capture_output=True, timeout=30, env=self.environment)
        self.assertEqual(result.returncode, code, result.stderr)
        return result

    def data(self, *args, **kwargs):
        return json.loads(self.call(*args, **kwargs).stdout)

    def scan(self):
        return self.data('scan', self.input, '--output', self.snapshot)

    def test_discovery_help_and_versions(self):
        version = plistlib.loads((ROOT / 'Resources/Info.plist').read_bytes())['CFBundleShortVersionString']
        self.assertEqual(self.call('--version').stdout.strip(), version)
        catalog = self.data('schema')
        names = {row['name'] for row in catalog['commands']}
        self.assertIn('history inspect', names)
        for name in sorted(names):
            detail = self.data('schema', *name.split())
            help_text = self.call(*name.split(), '--help').stdout
            self.assertIn('USAGE:', help_text)
            self.assertIn('USAGE:', detail['help'])
        self.assertIn('USAGE:', self.call().stdout)
        self.assertIn('#compdef', self.call('--generate-completion-script', 'zsh').stdout)

    def test_metadata_scan_and_bounded_projection(self):
        (self.input / '.hidden').write_bytes(b'hidden')
        os.link(self.input / 'a.txt', self.input / 'hardlink')
        (self.input / 'link').symlink_to(self.directory)
        before = self.digest()
        value = self.scan()
        self.assertEqual(value['schemaVersion'], 1)
        self.assertEqual(value['logicalBytes'], 2 * 3200 + 9 + 6 + (self.input / 'link').lstat().st_size)
        self.assertNotIn('children', value['largest'][0])
        self.assertEqual(self.digest(), before)
        self.assertEqual(stat.S_IMODE(self.snapshot.stat().st_mode), 0o600)
        self.assertEqual(value['status'], 'complete')

    def test_options_anywhere_equals_and_dash_paths(self):
        folder = self.directory / '-folder'
        folder.mkdir()
        (folder / 'file').write_bytes(b'contents')
        value = self.data('scan', '--output=' + str(self.snapshot), '--', '-folder')
        self.assertEqual(value['logicalBytes'], 8)
        result = self.data('inspect', '--limit=1', self.snapshot, '--metric=logical')
        self.assertEqual(result['returned'], 1)

    def test_query_pages_and_exact_folder(self):
        self.scan()
        first = self.data('inspect', self.snapshot, '--files', '--sort', 'name', '--order', 'asc', '--limit', 1)
        second = self.data('inspect', self.snapshot, '--files', '--sort', 'name', '--order', 'asc', '--limit', 1, '--offset', 1)
        self.assertEqual(first['nextOffset'], 1)
        self.assertEqual(first['entries'][0]['name'], 'a.txt')
        self.assertEqual(second['entries'][0]['name'], 'b.txt')
        self.assertNotIn('children', first['selected'])
        found = self.data('inspect', self.snapshot, '--query', 'Z.TXT')
        self.assertEqual(found['totalResults'], 1)
        self.assertEqual(self.data('inspect', self.snapshot, '--types', 'video')['entries'], [])
        missing = self.call('inspect', self.snapshot, '--path', '/not-in-snapshot', code=3)
        self.assertEqual(json.loads(missing.stderr)['error']['code'], 'not_found')

    def test_no_overwrite_including_dangling_symlink(self):
        self.snapshot.write_bytes(b'preserve me')
        value = self.call('scan', self.input, '--output', self.snapshot, code=1)
        self.assertEqual(json.loads(value.stderr)['error']['code'], 'output_exists')
        self.assertEqual(self.snapshot.read_bytes(), b'preserve me')
        self.snapshot.unlink()
        self.snapshot.symlink_to(self.directory / 'absent')
        self.call('scan', self.input, '--output', self.snapshot, code=1)
        self.assertTrue(self.snapshot.is_symlink())
        self.assertFalse((self.directory / 'absent').exists())

    def test_usage_errors_are_json_stderr_and_exit_two(self):
        cases = [('unknown',), ('scan',), ('scan', self.input, '--wat'),
                 ('inspect', self.snapshot, '--limit', '501'), ('inspect', self.snapshot, '--offset', '-1'),
                 ('scan', self.input, '--json', '--text'), ('scan', self.input, '--progress', '--quiet'),
                 ('duplicates', self.input, '--min-bytes', '-1'), ('duplicates', self.input, '--types', 'bogus'),
                 ('duplicates', self.input, '--modified-after', '2026-11-07T00:00:00Z',
                  '--modified-before', '2020-01-01T00:00:00Z'),
                 ('duplicates', self.input, '--output', 'unused.json')]
        for args in cases:
            with self.subTest(args=args):
                result = self.call(*args, code=2)
                self.assertEqual(result.stdout, '')
                self.assertEqual(json.loads(result.stderr)['error']['code'], 'usage')
        self.call('scan', self.directory / 'missing', code=3)

    def test_partial_and_cancelled_snapshots_never_report_complete(self):
        self.scan()
        snapshot = json.loads(self.snapshot.read_text())
        snapshot['issueCount'] = 1
        snapshot['issues'] = [{'path': '/illustrative/missing', 'message': 'not readable'}]
        self.snapshot.write_text(json.dumps(snapshot))
        partial = self.data('inspect', self.snapshot, code=4)
        self.assertEqual(partial['status'], 'partial')
        snapshot['cancelled'] = True
        self.snapshot.write_text(json.dumps(snapshot))
        self.assertEqual(self.data('inspect', self.snapshot, code=130)['status'], 'cancelled')

    def test_duplicate_plan_report_and_file_pagination(self):
        before = self.digest()
        estimate = self.data('duplicates', self.input)
        self.assertFalse(estimate['readContents'])
        self.assertEqual(estimate['candidateCount'], 2)
        output = self.directory / 'report.json'
        checked = self.data('duplicates', '--read-contents', self.input, '--output', output, '--limit', 1)
        self.assertEqual(checked['groupCount'], 1)
        self.assertEqual(checked['repeatedLogicalBytes'], 3200)
        self.assertEqual(stat.S_IMODE(output.stat().st_mode), 0o600)
        group = checked['groups'][0]['id']
        files = self.data('report', output, '--group', group, '--limit', 1)
        self.assertEqual(files['returned'], 1)
        self.assertEqual(files['nextOffset'], 1)
        self.assertNotIn('inode', files['files'][0])
        self.assertEqual(self.digest(), before)
        self.call('report', output, '--group', 'missing', code=3)

    def test_invalid_report_cannot_overflow_size_totals(self):
        output = self.directory / 'report.json'
        self.data('duplicates', self.input, '--read-contents', '--output', output)
        report = json.loads(output.read_text())
        for file in report['groups'][0]['files']:
            file['bytes'] = 2 ** 63 - 1
        # Three copies would overflow repeated-byte multiplication.
        third = dict(report['groups'][0]['files'][0])
        third['path'] += '.third'
        report['groups'][0]['files'].append(third)
        output.write_text(json.dumps(report))
        result = self.call('report', output, code=1)
        self.assertEqual(json.loads(result.stderr)['error']['code'], 'invalid_report')

    def test_closed_stdout_does_not_lose_export(self):
        process = subprocess.Popen([str(CLI), 'scan', str(self.input), '--output', str(self.snapshot)],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, cwd=self.directory, env=self.environment)
        process.stdout.close()
        errors = process.stderr.read()
        process.wait(timeout=10)
        process.stderr.close()
        self.assertEqual(process.returncode, 0, errors)
        self.assertTrue(self.snapshot.exists())
        self.assertEqual(self.data('inspect', self.snapshot)['totalResults'], 3)

    def test_progress_is_separate_ndjson(self):
        result = self.call('scan', self.input, '--progress')
        self.assertEqual(json.loads(result.stdout)['command'], 'scan')
        events = [json.loads(line) for line in result.stderr.splitlines()]
        self.assertTrue(events)
        self.assertTrue(all(event['event'] == 'progress' for event in events))
        self.assertEqual(self.call('scan', self.input, '--quiet').stderr, '')

    def test_signal_stops_scan_and_preserves_sources(self):
        # The first progress event is emitted only after signal handlers are registered.
        many = self.input / 'many'
        many.mkdir()
        for i in range(4000):
            (many / str(i)).touch()
        process = subprocess.Popen([str(CLI), 'scan', str(self.input), '--progress'],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=self.directory, env=self.environment)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        ready = selectors.DefaultSelector()
        ready.register(process.stderr, selectors.EVENT_READ)
        self.assertTrue(ready.select(10), 'No visible progress')
        line = process.stderr.readline()
        self.assertEqual(json.loads(line)['event'], 'progress')
        process.send_signal(signal.SIGINT)
        output, errors = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 130, errors)
        if output:
            self.assertEqual(json.loads(output)['status'], 'cancelled')
        self.assertEqual(len(list(many.iterdir())), 4000)
        ready.close()

    def test_install_is_idempotent_and_conflicts_preserve_files(self):
        directory = self.directory / 'bin with spaces'
        first = self.data('install', '--bin-dir', directory)
        self.assertTrue(first['changed'])
        self.assertFalse(self.data('install', '--bin-dir', directory)['changed'])
        link = directory / 'disk-atlas'
        self.assertTrue(link.is_symlink())
        link.unlink()
        link.write_text('owner content')
        self.call('install', '--bin-dir', directory, code=1)
        self.assertEqual(link.read_text(), 'owner content')

    def test_history_list_exposes_storage_and_ids_without_rescan(self):
        value = self.data('history', 'list', '--limit', 1)
        self.assertEqual(value['command'], 'history list')
        self.assertLessEqual(value['returned'], 1)
        for record in value['records']:
            self.assertIn('id', record)
            self.assertIn('storedBytes', record)
        self.call('history', 'inspect', 'not-a-uuid', code=2)

    def test_doctor_is_selected_diagnostics_not_environment(self):
        value = self.data('doctor')
        self.assertIn('defaultBinOnPath', value)
        self.assertNotIn('environment', value)
        self.assertNotIn('PATH', value)

    def test_text_escapes_filename_controls(self):
        (self.input / 'escape\x1b[31m.txt').write_bytes(b'x')
        output = self.call('scan', self.input, '--text').stdout
        self.assertNotIn('\x1b', output)
        self.assertGreater(len(output.splitlines()), 3)
        machine = self.data('scan', self.input)
        self.assertIn('escape\x1b[31m.txt', [item['name'] for item in machine['largest']])

    def test_mcp_compatibility_stdio(self):
        request = {'jsonrpc': '2.0', 'id': 1, 'method': 'tools/list'}
        result = subprocess.run([str(CLI), 'mcp'], input=json.dumps(request) + '\n',
                                capture_output=True, text=True, timeout=10, cwd=self.directory, env=self.environment)
        self.assertEqual(result.returncode, 0)
        tools = json.loads(result.stdout)['result']['tools']
        self.assertEqual(len(tools), 5)
        self.assertEqual(result.stderr, '')

    def digest(self):
        return {str(path.relative_to(self.input)): hashlib.sha256(path.read_bytes()).hexdigest()
                for path in self.input.rglob('*') if path.is_file() and not path.is_symlink()}
