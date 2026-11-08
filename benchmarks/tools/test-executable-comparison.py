"""Comparison evidence must reject missing samples and modified run inputs."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

TOOLS = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('verify_comparison', TOOLS/'verify-executable-comparison.py')
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix='nitro comparison ')
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        profile = TOOLS/'dosbox-x-486-high.conf'
        executable = self.root/'input.exe'; executable.write_bytes(b'MZ fixture')
        dpmi = self.root/'input-dpmi.exe'; dpmi.write_bytes(b'DPMI fixture')
        dosbox = self.root/'emulator.exe'; dosbox.write_bytes(b'emulator fixture')
        pak = self.root/'input.pak'; pak.write_bytes(b'PACK fixture')
        self.data = dict(profile=str(profile), profileSha256=verify.PROFILE_SHA,
                         inputs={v: str(executable) for v in verify.VARIANTS},
                         executableSha256={v: verify.sha(executable) for v in verify.VARIANTS},
                         dpmiProviderSha256=verify.sha(dpmi), gameDataSha256={'pak0.pak': verify.sha(pak)},
                         nitroVersion='NitroQuake fixture', dosbox=str(dosbox), results=[])
        for index, variant in enumerate(('original','quake486','nitro','quake486','nitro','original','nitro','original','quake486')):
            round_number = index//3+1
            stage = self.root/f'round-{round_number:02}-{variant}'
            data = stage/'quake/id1'; data.mkdir(parents=True)
            (stage/'quake/quake.exe').write_bytes(executable.read_bytes())
            (stage/'quake/cwsdpmi.exe').write_bytes(dpmi.read_bytes())
            (data/'pak0.pak').write_bytes(pak.read_bytes())
            (data/'bench.cfg').write_text('viewsize 100\nstartdemos\ntimedemo demo1\n')
            (stage/'dosbox-x.conf').write_bytes(profile.read_bytes())
            log = data/'qconsole.log'; log.write_text('320x200\n969 frames 60.0 seconds 16.2 fps\n')
            self.data['results'].append(dict(round=round_number, variant=variant, consoleLog=str(log), frames=969, seconds=60.0, fps=16.2))
        (self.root/'nitro-build-manifest.json').write_text(json.dumps(dict(benchmarkBuild=False, profileBuild=False,
            isaAuditStatus='PASS', sourceBoundIsa=True, executableSha256=verify.sha(executable))))
        self.save()

    def save(self):
        (self.root/'results.json').write_text(json.dumps(self.data))

    def test_complete_record_is_summarized(self):
        result = verify.verify(self.root)
        self.assertTrue(result['verified'])
        self.assertEqual(result['runs'], 9)

    def test_missing_sample_is_rejected(self):
        self.data['results'].pop(); self.save()
        with self.assertRaisesRegex(ValueError, 'Missing, duplicated or reordered'):
            verify.verify(self.root)

    def test_modified_staged_pak_is_rejected(self):
        (self.root/'round-01-original/quake/id1/pak0.pak').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError, 'Game data mismatch'):
            verify.verify(self.root)

    def test_unreported_completed_sample_is_rejected(self):
        extra = self.root/'round-unreported/quake/id1'; extra.mkdir(parents=True)
        (extra/'qconsole.log').write_text('969 frames 59.0 seconds 16.4 fps')
        with self.assertRaisesRegex(ValueError, 'Completed sample excluded'):
            verify.verify(self.root)

    def test_measurement_command_queue_is_guarded(self):
        (self.root/'round-01-original/quake/id1/bench.cfg').write_text('timedemo demo1\nquit\n')
        with self.assertRaisesRegex(ValueError, 'command queue changed'):
            verify.verify(self.root)


if __name__ == '__main__':
    unittest.main()
