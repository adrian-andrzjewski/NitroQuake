"""Audit recorded whole-engine profiles and generate ranked elapsed-time reports."""
from __future__ import annotations
import argparse
import csv
import hashlib
import html
import json
import math
from pathlib import Path
import statistics


def read(path):return json.loads(path.read_text(encoding='utf-8-sig'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def ranked(profile):
    """Exclusive times only: inclusive parent and child costs must never be added."""
    calibration=profile['instrumentation']['read_seconds']
    if not math.isfinite(calibration) or calibration<=0:raise ValueError('Missing positive finite timer calibration')
    if profile['profiler']['stack_overflows'] or profile['profiler']['bad_leaves']:
        raise ValueError('Invalid native profiling stack')
    frames=profile['benchmark']['demo_frames']
    if frames<=0:raise ValueError('Missing positive measured frame count')
    rows=[]
    for node in profile['nodes']:
        if node['instr_reads']<0:raise ValueError('Negative timer-read count')
        if any(not math.isfinite(node[key]) or node[key]<0 for key in ['inclusive_seconds','self_seconds']):
            raise ValueError('Non-finite or negative native scope time')
        floor=node['instr_reads']*calibration
        corrected=node['self_seconds']-floor
        rows.append(dict(node=node['id'],calls=node['calls'],raw_seconds=node['self_seconds'],
            corrected_seconds=max(0,corrected),timer_floor_seconds=floor,
            below_floor=corrected<0,signal_fraction=corrected/node['self_seconds'] if node['self_seconds'] else 0,
            corrected_ms_per_frame=1000*max(0,corrected)/frames))
    total=sum(r['corrected_seconds'] for r in rows)
    if not total:raise ValueError('No measurable self time')
    for row in rows:row['corrected_share_percent']=100*row['corrected_seconds']/total
    return sorted(rows,key=lambda r:r['corrected_seconds'],reverse=True)


def category(node):
    if node=='renderer':return 'Renderer'
    if node in ['server','server-clients','server-physics','server-messages','quakec','collision']:return 'Local server'
    if node in ['game','client-read']:return 'Client / network'
    if node in ['audio','sound-spatial','sound-mix','cd-audio']:return 'Audio'
    if node=='present':return 'Video transfer'
    if node=='input':return 'Input / commands'
    if node=='frame':return 'Frame residual'
    return 'Screen / view / HUD'


def component(node):
    if node in ['surfaces','surface-cache','gradients','texture-spans','z-spans','sky-spans','turbulent-spans','solid-spans']:
        return 'Surface / texture / Z / cache'
    if node.startswith('alias-') or node in ['entities','viewmodel','sprites']:
        return 'Models / sprites'
    if node in ['world-bsp','renderface']:return 'World BSP / faces'
    if node in ['edge-drawing','edge-scan']:return 'Edges / dispatch'
    if node=='brush-entities':return 'Brush entities'
    if node in ['setup','visibility']:return 'Setup / PVS'
    if node=='warp':return 'Screen warp'
    if node=='particles':return 'Particles'
    return category(node)


def analyze(root):
    session=read(root/'session.json')
    if session['status']!='complete':raise ValueError('Analyze completed sessions only')
    runs=[]; groups={}; flat=[]
    for job in session['jobs']:
        path=root/job['file']
        if sha(path)!=job['sha256']:raise ValueError('Measurement result hash changed')
        data=read(path)
        if data.get('diagnosticLog'):raise ValueError('Console-log diagnostics are not timing evidence')
        label=f"{job['workload']}, sound {'on' if job['sound'] else 'off'}"
        group=groups.setdefault(label,dict(workload=job['workload'],sound=job['sound'],modes={},checksums={}))
        group['modes'].setdefault(job['mode'],[]).append(data['seconds'])
        group['checksums'].setdefault(job['mode'],[]).append(job['checksums'])
        entry=dict(name=job['name'],label=label,mode=job['mode'],frames=data['frames'],seconds=data['seconds'],fps=data['fps'])
        if data['profile']:
            entry['ranking']=ranked(data['profile'])
            entry['captureMode']=data['profile']['capture_mode']
            entry['timerReads']=data['profile']['profiler']['timer_reads']
            entry['timerReadSeconds']=data['profile']['instrumentation']['read_seconds']
            entry['categories']={}
            for row in entry['ranking']:
                item=dict(run=job['name'],mode=job['mode'],**row);flat.append(item)
                key=category(row['node'])
                entry['categories'][key]=entry['categories'].get(key,0)+row['corrected_ms_per_frame']
        runs.append(entry)
    for label,group in groups.items():
        baseline=statistics.median(group['modes']['off'])
        group['medianSeconds']={mode:statistics.median(values) for mode,values in group['modes'].items()}
        group['elapsedOverheadPercent']={mode:100*(value/baseline-1) for mode,value in group['medianSeconds'].items() if mode!='off'}
        all_checks=[json.dumps(c,sort_keys=True) for values in group['checksums'].values() for c in values]
        group['allFinalChecksumsMatch']=len(set(all_checks))==1
        coarse=[r for r in runs if r['label']==label and r['mode']=='coarse']
        keys=sorted({key for run in coarse for key in run['categories']})
        medians={key:statistics.median(run['categories'].get(key,0) for run in coarse) for key in keys}
        total=sum(medians.values())
        group['coarseMsPerFrame']=medians
        group['coarseSharePercent']={key:100*value/total for key,value in medians.items()}
        group['conditionalFpsGains']={key:{str(fraction):100*(1/(1-value/total*fraction)-1)
            for fraction in [.1,.25,.5]} for key,value in medians.items()}
        parts=[r for r in runs if r['label']==label and r['mode']=='parts']
        if parts:
            nodes=sorted({row['node'] for run in parts for row in run['ranking']})
            group['componentNodeMsPerFrame']={node:statistics.median(next(row['corrected_ms_per_frame'] for row in run['ranking'] if row['node']==node) for run in parts) for node in nodes}
            grouped={}
            for node,value in group['componentNodeMsPerFrame'].items():
                key=component(node);grouped[key]=grouped.get(key,0)+value
            total=sum(grouped.values())
            group['componentMsPerFrame']=grouped
            group['componentSharePercent']={key:100*value/total for key,value in grouped.items()}
    result=dict(schemaVersion=1,sourceSessionSha256=sha(root/'session.json'),groups=groups,runs=runs,
        definitions='Timer-only corrected exclusive scope time. Coarse mode disables dense premise counters. Correction excludes profiler bookkeeping, layout and DMA feedback. Amdahl gains are conditional scenarios, not measured optimizations.',
        generatorSha256=sha(Path(__file__)))
    (root/'analysis.json').write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    with (root/'ranked-scopes.csv').open('w',newline='',encoding='utf-8') as stream:
        writer=csv.DictWriter(stream,fieldnames=list(flat[0]));writer.writeheader();writer.writerows(flat)
    plot(root,result)
    write_index(root,result)
    return result


def write_index(root,result):
    rows=[]
    for label,group in result['groups'].items():
        frames=next(run['frames'] for run in result['runs'] if run['label']==label and run['mode']=='off')
        overhead=group['elapsedOverheadPercent']
        rows.append('<tr><td>'+html.escape(label)+'</td>'+
            f'<td>{frames/group["medianSeconds"]["off"]:.4f}</td>'+
            ''.join(f'<td>{overhead.get(mode,0):.2f}%</td>' for mode in ['coarse','parts','detailed'])+
            '<td>'+('MATCH' if group['allFinalChecksumsMatch'] else 'MISMATCH: inspect raw data')+'</td></tr>')
    document='''<!doctype html><meta charset="utf-8"><title>NitroQuake whole-engine profiles</title>
<style>body{max-width:1250px;margin:35px auto;padding:0 20px;font:16px/1.5 system-ui;color:#24364a}img{max-width:100%}td,th{padding:8px;border-bottom:1px solid #ccd;text-align:left}table{border-collapse:collapse;width:100%}</style>
<h1>NitroQuake whole-engine profiling</h1><p>DOSBox-X i486 profile, VGA 320×200. Fixed simulation advancement, real DOS timer. These are elapsed-time measurements, not physical processor cycles.</p>
<table><tr><th>Workload / device</th><th>Control FPS</th><th>Coarse overhead</th><th>Components overhead</th><th>Detailed overhead</th><th>Final checksums</th></tr>'''+''.join(rows)+'''</table>
<p>Overhead compares profiled and control executables: it includes observer bookkeeping, code layout and possible DMA feedback. Positive timing cost is not an engine regression. Timer correction alone does not remove all observer effects.</p>
<h2>Coarse attribution</h2><img src="whole-engine-breakdown.png"><h2>Component attribution</h2><img src="component-breakdown.png">
<p><a href="analysis.json">Full analysis and conditional Amdahl scenarios</a> · <a href="ranked-scopes.csv">Ranked exclusive scope CSV</a> · <a href="session.json">Session, samples and source pins</a></p>
<p>Inclusive parent and child costs overlap. Only exclusive times are summed. Local server checksums cover selected numeric fields, not exhaustive global simulation state. Audio follows real DMA time; inspect differing checksums before treating device comparisons as matched work.</p>'''
    (root/'report.html').write_text(document,encoding='utf-8')


def plot(root,result):
    import matplotlib
    matplotlib.use('Agg')
    matplotlib.rcParams['svg.hashsalt']='nitroquake-engine-profile-v1'
    import matplotlib.pyplot as plt
    categories=['Renderer','Screen / view / HUD','Video transfer','Local server','Client / network','Audio','Input / commands','Frame residual']
    labels=list(result['groups']);positions=range(len(labels));left=[0.0]*len(labels)
    fig,ax=plt.subplots(figsize=(13,6))
    for key in categories:
        values=[result['groups'][label]['coarseSharePercent'].get(key,0) for label in labels]
        ax.barh(positions,values,left=left,label=key)
        left=[a+b for a,b in zip(left,values)]
    ax.set_yticks(list(positions),labels);ax.invert_yaxis();ax.set_xlim(0,100)
    ax.set_xlabel('Share of timer-corrected exclusive coarse scope time (%)')
    ax.set_title('NitroQuake at 320×200: whole-engine elapsed-time attribution')
    ax.legend(loc='upper center',bbox_to_anchor=(.5,-.15),ncol=4,fontsize=8)
    fig.text(.02,.01,'DOSBox-X dynamic i486 profile. Not physical CPU cycles. Profiling overhead and replay checks are recorded separately.',fontsize=8)
    fig.tight_layout(rect=(0,.10,1,1))
    for ext in ['png','svg']:fig.savefig(root/('whole-engine-breakdown.'+ext),dpi=150,metadata={'Creator':'NitroQuake engine analysis','Date':None} if ext=='svg' else None)
    plt.close(fig)
    fig,ax=plt.subplots(figsize=(13,7))
    keys=sorted({key for group in result['groups'].values() for key in group.get('componentSharePercent',{})})
    left=[0.0]*len(labels)
    for index,key in enumerate(keys):
        values=[result['groups'][label].get('componentSharePercent',{}).get(key,0) for label in labels]
        ax.barh(positions,values,left=left,label=key,color=plt.get_cmap('tab20')(index%20))
        left=[a+b for a,b in zip(left,values)]
    ax.set_yticks(list(positions),labels);ax.invert_yaxis();ax.set_xlim(0,100)
    ax.set_xlabel('Share of timer-corrected exclusive component scope time (%)')
    ax.set_title('Major rendering and gameplay components; dense premise counters disabled')
    ax.legend(loc='upper center',bbox_to_anchor=(.5,-.12),ncol=4,fontsize=8)
    fig.text(.02,.01,'DOSBox elapsed-time attribution. Scope overhead beyond timer reads remains; compare with coarse/control runs.',fontsize=8)
    fig.tight_layout(rect=(0,.16,1,1))
    for ext in ['png','svg']:fig.savefig(root/('component-breakdown.'+ext),dpi=150,metadata={'Creator':'NitroQuake engine analysis','Date':None} if ext=='svg' else None)
    plt.close(fig)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('directory',type=Path)
    args=parser.parse_args();result=analyze(args.directory)
    for label,group in result['groups'].items():
        print(label,group['elapsedOverheadPercent'],'checksums match:',group['allFinalChecksumsMatch'])
