"""Numerical, corruption and comparison contracts for frame timelines."""
import csv
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

import frame_times as ft


class FrameTimesTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='frame timeline ')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def raw(self, values, name='raw.csv'):
        path = self.root/name
        with path.open('w', newline='') as stream:
            writer = csv.writer(stream)
            writer.writerow(['sample_index', 'elapsed_seconds', 'frame_seconds'])
            writer.writerows(values)
        return path

    def test_preserves_playback_order_and_real_gaps(self):
        rows = ft.read_samples(self.raw([(0, .02, .02), (1, .06, .03), (2, .08, .01)]), 3)
        self.assertEqual([r['frame_ms'] for r in rows], [20, 30, 10])
        stats = ft.summarize(rows, .08)
        self.assertAlmostEqual(stats['average_fps'], 37.5)
        self.assertAlmostEqual(stats['sample_throughput_fps'], 50)
        self.assertAlmostEqual(stats['inter_frame_gap_seconds'], .02)
        self.assertEqual(stats['slowest_frames'][0]['sample_index'], 1)

    def test_slow_percent_low_uses_durations_not_mean_of_fps(self):
        values=[]; elapsed=0
        for index, duration in enumerate([.01]*198+[.1, .2]):
            elapsed += duration; values.append((index, elapsed, duration))
        stats = ft.summarize(ft.read_samples(self.raw(values), 200), elapsed)
        self.assertAlmostEqual(stats['low_1_percent_fps'], 1/.15)
        self.assertEqual(stats['slowest_1_percent_frames'], 2)
        self.assertAlmostEqual(stats['frame_time_percentiles_ms']['p99'], 10)
        self.assertAlmostEqual(stats['frame_time_percentiles_ms']['p99_9'], 200)

    def test_inter_frame_stall_is_visible_in_instantaneous_fps(self):
        rows=ft.read_samples(self.raw([(0,.01,.01),(1,.11,.01)]),2)
        self.assertAlmostEqual(rows[1]['work_fps'],100)
        self.assertAlmostEqual(rows[1]['instantaneous_fps'],10)
        self.assertAlmostEqual(rows[1]['inter_frame_gap_ms'],90)
        stats=ft.summarize(rows,.11)
        self.assertAlmostEqual(stats['minimum_fps'],10)

    def test_missing_duplicate_and_out_of_order_rows_fail(self):
        for values in [[(0, .01, .01)], [(0, .01, .01), (0, .02, .01)],
                       [(1, .01, .01), (0, .02, .01)]]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                ft.read_samples(self.raw(values), 2)

    def test_non_finite_zero_negative_overlapping_and_extra_samples_fail(self):
        for values in [[(0, .01, float('nan'))], [(0, float('inf'), .01)],
                       [(0, .01, 0)], [(0, .01, -.01)], [(0, .01, .02)],
                       [(0, .01, .01), (1, .02, .01)]]:
            with self.subTest(values=values), self.assertRaises(ValueError):
                ft.read_samples(self.raw(values), 1)

    def test_float32_endpoint_rounding_is_tolerated(self):
        rows = ft.read_samples(self.raw([(0, 32, 32), (1, 32.009998, .01)]), 2)
        self.assertEqual(len(rows), 2)

    def test_wrong_header_is_rejected(self):
        p=self.root/'wrong.csv'; p.write_text('fps,time\n10,1\n')
        with self.assertRaisesRegex(ValueError, 'header'): ft.read_samples(p, 1)

    def fixture(self):
        stage = self.root/'stage'; data = stage/'quake/id1'; data.mkdir(parents=True)
        (stage/'quake/qbench.exe').write_bytes(b'MZ benchmark')
        (stage/'quake/cwsdpmi.exe').write_bytes(b'provider')
        (data/'pak0.pak').write_bytes(b'PACK data')
        ft.write_json(stage/'staged-data.json', [dict(name='pak0.pak', sha256=ft.sha256(data/'pak0.pak'))])
        ft.write_json(stage/'tooling-provenance.json', dict(gitRevision='fixture', dirty=False, files={}))
        raw=self.raw([(0, .01, .01), (1, .03, .02)])
        protocol=dict(demos={'demo1':2}, autoexecCommands=['host_framerate 0.0625'],
                      quakeExtraArgs='-stdvid', dosboxProfileSha256='ABC')
        source=dict(cpuTarget='i486', demo='demo1', autoexecCommands=protocol['autoexecCommands'],
            quakeExtraArgs='-stdvid', profileSha256='ABC', isaAuditStatus='PASS', frameFpsStats=True,
            instrumentation=False, dosboxVersion='fixture', dosboxExecutableSha256='exe-hash',
            stagingRoot=str(stage), sourceFingerprint='native-build', sourceTreeFingerprint='native-source',
            dpmiHost='cwsdpmi', dpmiHostSha256=ft.sha256(stage/'quake/cwsdpmi.exe'),
            results=[dict(frames=2, seconds=.03, report='framebuffer-checksum 123', frameTimesPath=str(raw),
                fpsStats=dict(frame_timing=dict(schema=1,width=320,height=200),
                    fps=dict(stored_frames=2, measured_frames=2, overflow_frames=0, invalid_frames=0,timer_reads=4),
                    benchmark=dict(frames=2,duration_seconds=.03)))])
        path=self.root/'source.json'; ft.write_json(path,source)
        return path, source, protocol

    def test_full_ingestion_persists_verifiable_ordered_data(self):
        path, source, protocol=self.fixture()
        out=self.root/'run'
        report, rows=ft.ingest(path,out,'baseline',protocol)
        self.assertEqual(report['framebufferChecksum'],123)
        loaded, recovered=ft.load_run(out)
        self.assertEqual(loaded, report); self.assertEqual(rows,recovered)
        (out/'frames.csv').write_text('tampered')
        with self.assertRaisesRegex(ValueError,'hash'):ft.load_run(out)

    def test_ingestion_rejects_incomplete_profile_fixed_clock_and_wrong_resolution(self):
        path, source, protocol=self.fixture()
        for mutate in [lambda j:j.update(instrumentation=True),
                       lambda j:j.update(deterministicPresentationClock=True),
                       lambda j:j['results'][0]['fpsStats']['fps'].update(overflow_frames=1),
                       lambda j:j['results'][0]['fpsStats']['frame_timing'].update(width=640),
                       lambda j:j.update(profileSha256='different')]:
            variant=json.loads(json.dumps(source)); mutate(variant); ft.write_json(path,variant)
            with self.subTest(variant=variant), self.assertRaises(ValueError):
                ft.ingest(path,self.root/'rejected','candidate',protocol)

    def test_modified_staged_game_data_is_rejected(self):
        path, source, protocol=self.fixture()
        (Path(source['stagingRoot'])/'quake/id1/pak0.pak').write_bytes(b'changed')
        with self.assertRaisesRegex(ValueError,'PAK changed'):
            ft.ingest(path,self.root/'rejected','baseline',protocol)

    def test_comparison_checks_environment_and_aligns_indices(self):
        path, source, protocol=self.fixture()
        spec=importlib.util.spec_from_file_location('frame_benchmark',Path(__file__).with_name('frame-benchmark.py'))
        tool=importlib.util.module_from_spec(spec); spec.loader.exec_module(tool)
        roots=[]
        for label, factor in [('old',1),('new',.5)]:
            root=self.root/label; root.mkdir()
            raw=self.raw([(0,.01*factor,.01*factor),(1,.03*factor,.02*factor)],label+'.csv')
            variant=json.loads(json.dumps(source)); variant['results'][0]['frameTimesPath']=str(raw)
            variant['results'][0]['seconds']=.03*factor
            variant['results'][0]['fpsStats']['benchmark']['duration_seconds']=.03*factor
            ft.write_json(path,variant)
            report,_=ft.ingest(path,root/'demo1-run-01',label,protocol)
            samples=[dict(demo='demo1',repetition=1,directory='demo1-run-01',statistics=report['statistics'])]
            ft.write_json(root/'session.json',dict(status='complete',label=label,samples=samples,aggregate=tool.aggregate(samples)))
            roots.append(root)
        tool.compare_sessions(*roots,self.root/'comparison')
        comparison=ft.read_json(self.root/'comparison/comparison.json')['demos']['demo1']
        self.assertAlmostEqual(comparison['averageFpsChangePercent'],100)
        self.assertAlmostEqual(comparison['p99FrameTimeChangePercent'],-50)
        p=roots[1]/'demo1-run-01/statistics.json'; report=ft.read_json(p)
        report['environment']['dpmiSha256']='incompatible'; ft.write_json(p,report)
        with self.assertRaisesRegex(ValueError,'Incompatible'):
            tool.compare_sessions(*roots,self.root/'rejected-comparison')


if __name__ == '__main__': unittest.main()
