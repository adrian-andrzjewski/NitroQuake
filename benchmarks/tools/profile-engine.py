"""Collect a frozen, serial matrix of whole-engine DOSBox profile/control runs."""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def collect(args):
    if not 16<=args.frames<=4096 or args.timeout<=0:
        raise ValueError('Frames must be 16..4096 and timeout must be positive')
    if len(set(args.workloads))!=len(args.workloads):raise ValueError('Workloads must be unique')
    root=args.output.resolve()
    if root.exists():raise ValueError('Choose a fresh output directory')
    runner=Path(__file__).resolve().with_name('engine-profile-dos.ps1')
    pwsh=shutil.which('pwsh')
    if not pwsh:raise ValueError('PowerShell 7 is required')
    root.mkdir(parents=True)
    jobs=[]
    for repetition in range(1,args.runs+1):
        workloads=args.workloads[repetition-1:]+args.workloads[:repetition-1]
        for workload in workloads:
            for sound in ([False] if workload.startswith('demo') else [False,True]):
                # Check scope integrity before spending a control run on a new workload.
                for mode in (['coarse','off','parts'] if repetition==1 else ['parts','off']):
                    jobs.append((workload,sound,mode,repetition))
    for workload in args.workloads:
        for sound in ([False] if workload.startswith('demo') else [False,True]):
            jobs.append((workload,sound,'detailed',1))
    session=dict(schemaVersion=1,status='running',runnerSha256=digest(runner),
        collectorSha256=digest(Path(__file__)),rendererProfile=args.renderer_profile,
        rendererProfileSha256=None,
        jobs=[],plannedJobs=len(jobs),frames=args.frames,builds={},
        startedUtc=datetime.now(timezone.utc).isoformat())
    shutil.copyfile(runner,root/runner.name)
    shutil.copyfile(Path(__file__),root/Path(__file__).name)
    def save(): (root/'session.json').write_text(json.dumps(session,indent=2)+'\n')
    save();started=time.monotonic()
    try:
        for workload,sound,mode,repetition in jobs:
            name=f'{workload}-sound{int(sound)}-{mode}-{repetition}'
            print(name,flush=True)
            command=[pwsh,'-NoProfile','-File',str(runner),'-LocalOutputDirectoryName',
                args.control_build if mode=='off' else args.profile_build,
                '-Workload',workload,'-Mode',mode,'-Frames',str(args.frames),
                '-RendererProfile',args.renderer_profile,
                '-TimeoutSeconds',str(args.timeout),'-ResultJson',str(root/(name+'.json'))]
            if args.game_root:command+=['-GameRoot',str(args.game_root.resolve())]
            if args.data_root:command+=['-DataRoot',str(args.data_root.resolve())]
            if args.tool_root:command+=['-ToolRoot',str(args.tool_root.resolve())]
            if mode!='off':command+=['-Instrumentation']
            if sound:command+=['-Sound']
            with (root/(name+'.log')).open('w',encoding='utf-8') as log:
                log.write(json.dumps(command)+'\n');log.flush()
                process=subprocess.Popen(command,stdout=log,stderr=subprocess.STDOUT)
                try:code=process.wait(timeout=args.timeout+120)
                except BaseException:
                    subprocess.run(['taskkill','/PID',str(process.pid),'/T','/F'],capture_output=True)
                    process.wait();raise
            if code:raise RuntimeError(f'{name} failed ({code}); retained log: {root/(name+".log")}')
            if digest(runner)!=session['runnerSha256']:raise ValueError('Runner changed during collection')
            data=json.loads((root/(name+'.json')).read_text(encoding='utf-8-sig'))
            environment=dict(dosbox=data['dosboxSha256'],profile=data['profileSha256'],
                provider=data['providerVerification']['sha256'],
                paks={p['name']:p['sha256'] for p in data['stagedData']})
            if 'environment' in session and session['environment']!=environment:
                raise ValueError('Emulator, provider or input data changed during collection')
            session['environment']=environment
            if data.get('rendererProfile')!=args.renderer_profile:
                raise ValueError('Renderer profile changed during collection')
            renderer_profile_sha=data.get('rendererProfileSha256')
            if 'rendererProfileSha256' in session and session['rendererProfileSha256'] not in (None,renderer_profile_sha):
                raise ValueError('Renderer profile file changed during collection')
            session['rendererProfileSha256']=renderer_profile_sha
            source_tree=data['sourceTreeFingerprint']
            if 'sourceTreeFingerprint' in session and session['sourceTreeFingerprint']!=source_tree:
                raise ValueError('Native source tree changed during collection')
            session['sourceTreeFingerprint']=source_tree
            variant='control' if mode=='off' else 'profile'
            build=dict(executableSha256=data['executableSha256'],sourceFingerprint=data['sourceFingerprint'])
            if variant in session['builds'] and session['builds'][variant]!=build:
                raise ValueError('Native build changed during collection')
            if variant not in session['builds']:
                session['builds'][variant]=build
                manifest=Path(data['buildVerification']['manifest'])
                if digest(manifest).upper()!=data['buildVerification']['manifestSha256'].upper():
                    raise ValueError('Native manifest changed after measurement')
                shutil.copyfile(manifest,root/(variant+'-build-manifest.json'))
            fields=['framebuffer-checksum']+([] if workload.startswith('demo') else ['simulation-checksum'])
            checksums={field:re.search(field+r' (\d+)',data['report'])[1] for field in fields}
            session['jobs'].append(dict(name=name,file=name+'.json',sha256=digest(root/(name+'.json')),
                workload=workload,sound=sound,mode=mode,repetition=repetition,checksums=checksums))
            save()
        session['status']='complete'
    except BaseException as error:
        session['status']='failed';session['error']=str(error);raise
    finally:
        session['wallSeconds']=time.monotonic()-started
        session['finishedUtc']=datetime.now(timezone.utc).isoformat();save()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--control-build',required=True)
    parser.add_argument('--profile-build',required=True)
    parser.add_argument('--game-root',type=Path)
    parser.add_argument('--data-root',type=Path)
    parser.add_argument('--tool-root',type=Path)
    parser.add_argument('--renderer-profile',choices=['benchmark-control','i486-release'],default='benchmark-control')
    parser.add_argument('--runs',type=int,default=2,choices=[1,2,3])
    parser.add_argument('--frames',type=int,default=256)
    parser.add_argument('--timeout',type=int,default=600)
    parser.add_argument('--workloads',nargs='+',default=['demo1','demo2','demo3','e1m1','e1m2'],choices=['demo1','demo2','demo3','e1m1','e1m2'])
    collect(parser.parse_args())
