"""Check exclusive attribution math and reject invalid profiler evidence."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('engine_analysis',Path(__file__).with_name('analyze-engine-profiles.py'))
tool=importlib.util.module_from_spec(spec);spec.loader.exec_module(tool)


class AttributionTests(unittest.TestCase):
    def fixture(self):
        return dict(instrumentation=dict(read_seconds=.01),
            profiler=dict(stack_overflows=0,bad_leaves=0),benchmark=dict(demo_frames=100),nodes=[
                dict(id='frame',calls=100,inclusive_seconds=3,self_seconds=1,instr_reads=4),
                dict(id='renderer',calls=100,inclusive_seconds=2,self_seconds=2,instr_reads=1),
                dict(id='input',calls=100,inclusive_seconds=.001,self_seconds=.001,instr_reads=1)])

    def test_corrects_timer_floor_without_double_counting_inclusive_parents(self):
        rows=tool.ranked(self.fixture())
        self.assertEqual(rows[0]['node'],'renderer')
        self.assertAlmostEqual(rows[0]['corrected_seconds'],1.99)
        self.assertAlmostEqual(rows[0]['corrected_ms_per_frame'],19.9)
        self.assertAlmostEqual(sum(r['corrected_share_percent'] for r in rows),100)
        self.assertAlmostEqual(rows[0]['corrected_share_percent'],100*1.99/(1.99+.96))
        low=next(r for r in rows if r['node']=='input')
        self.assertTrue(low['below_floor']);self.assertEqual(low['corrected_seconds'],0)

    def test_rejects_missing_calibration_and_corrupt_scope_stack(self):
        for key in ['stack_overflows','bad_leaves']:
            data=self.fixture();data['profiler'][key]=1
            with self.subTest(key=key),self.assertRaises(ValueError):tool.ranked(data)
        for value in [0, float('nan'), float('inf')]:
            data=self.fixture();data['instrumentation']['read_seconds']=value
            with self.subTest(calibration=value),self.assertRaises(ValueError):tool.ranked(data)
        data=self.fixture();data['benchmark']['demo_frames']=0
        with self.assertRaises(ValueError):tool.ranked(data)
        for key,value in [('instr_reads',-1),('self_seconds',float('nan')),('inclusive_seconds',-1)]:
            data=self.fixture();data['nodes'][0][key]=value
            with self.subTest(field=key),self.assertRaises(ValueError):tool.ranked(data)

    @unittest.skipUnless(shutil.which('pwsh'),'PowerShell 7 is required')
    def test_oversized_local_script_rejected_before_build_or_dosbox(self):
        with tempfile.TemporaryDirectory() as directory:
            result=Path(directory)/'unexpected.json'
            run=subprocess.run([shutil.which('pwsh'),'-NoProfile','-File',
                str(Path(__file__).with_name('engine-profile-dos.ps1')),
                '-LocalOutputDirectoryName','intentionally-unbuilt-command-budget-test',
                '-Workload','e1m1','-Mode','off','-Frames','4096','-ResultJson',str(result)],
                capture_output=True,text=True,timeout=30)
            self.assertNotEqual(run.returncode,0)
            self.assertIn('command-buffer budget',run.stdout+run.stderr)
            self.assertFalse(result.exists())


if __name__=='__main__':unittest.main()
