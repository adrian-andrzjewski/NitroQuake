"""Build and run the native QuakeC interpreter differential fixture."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

from _workspace import BENCHMARK_TOOLS, game_root


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def function(source):
    masked = re.sub(r'/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'',
                    lambda match: ' ' * len(match[0]), source, flags=re.S)
    start = masked.index('void PR_ExecuteProgram (func_t fnum)')
    brace = masked.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (masked[end] == '{') - (masked[end] == '}')
        end += 1
    return source[:start], source[start:end]


def verify(args):
    if not 30 <= args.timeout <= 1800:
        raise ValueError('Timeout must be 30..1800 seconds')
    reference = game_root(args.reference_root)
    candidate = game_root(args.game_root)
    output = args.output.resolve()
    if output.exists():
        raise ValueError('Choose a fresh output directory')
    sources = [(root / 'src/pr_exec.c').read_text(encoding='utf-8-sig')
               for root in (reference, candidate)]
    before, after = [function(source) for source in sources]
    if before[0] != after[0]:
        raise ValueError('Shared interpreter helpers changed; this fixture requires an unchanged helper prefix')
    headers = []
    for root in (reference, candidate):
        headers.append({path.relative_to(root / 'src').as_posix():
                        path.read_bytes().replace(b'\r\n', b'\n')
                        for path in (root / 'src').rglob('*.h')})
    if headers[0] != headers[1]:
        raise ValueError('Reference and candidate headers differ; review the fixture ABI before comparing')
    pwsh = shutil.which('pwsh')
    if not pwsh:
        raise ValueError('PowerShell 7 is required')
    manifest = json.loads((candidate / 'tools/dos-toolchain.json').read_text())
    tool_root = (args.tool_root or Path(os.environ['LOCALAPPDATA']) / '486quake/tools').resolve()
    compiler = tool_root / manifest['djgpp']['installDirectory'] / manifest['djgpp']['compiler']
    if not compiler.is_file():
        raise ValueError('Install the game compiler toolchain before running the fixture')
    resolved = json.loads(subprocess.run([
        pwsh, '-NoProfile', '-File', str(candidate / 'tools/build-dos.ps1'),
        '-Benchmark', '-CpuTarget', 'i486', '-LocalOutputDirectoryName', 'qc-fixture', '-DumpFlags'],
        check=True, capture_output=True, text=True).stdout)
    flags = resolved['cFlags'] + resolved.get('cSourceExtraFlags', {}).get('pr_exec.c', [])
    output.mkdir(parents=True)
    state = dict(schemaVersion=1, status='building', reference=str(reference), candidate=str(candidate),
                 sourceSha256={str(root): digest(root / 'src/pr_exec.c') for root in (reference, candidate)},
                 compiler=str(compiler), compilerSha256=digest(compiler), flags=flags,
                 driverSha256=digest(__file__), headerCount=len(headers[0]),
                 normalizedHeaderSha256={name: hashlib.sha256(data).hexdigest()
                                         for name, data in sorted(headers[0].items())})

    def save():
        (output / 'fixture.json').write_text(json.dumps(state, indent=2) + '\n', encoding='utf-8')

    save()
    try:
        (output / 'control.c').write_text(sources[0].replace(
            'void PR_ExecuteProgram (', 'void PR_ExecuteProgramControl (', 1), encoding='utf-8')
        declarations = ('#include "quakedef.h"\nextern int pr_depth,pr_xstatement;\n'
                        'int PR_EnterFunction(dfunction_t *f);\nint PR_LeaveFunction(void);\n'
                        'void PR_PrintStatement(dstatement_t *s);\n')
        (output / 'candidate.c').write_text(declarations + after[1].replace(
            'void PR_ExecuteProgram (', 'void PR_ExecuteProgramCandidate (', 1), encoding='utf-8')
        shutil.copyfile(BENCHMARK_TOOLS / 'fixtures/qc-interpreter-cases.c', output / 'fixture.c')
        for name in ('control', 'candidate', 'fixture'):
            subprocess.run([str(compiler), *flags, '-Wall', '-c', str(output / (name + '.c')),
                            '-o', str(output / (name + '.obj'))], check=True)
        subprocess.run([str(compiler), '-march=i486', '-mtune=i486', '-mfpmath=387',
                        *[str(output / (name + '.obj')) for name in ('fixture', 'candidate', 'control')],
                        '-o', str(output / 'fixture.exe')], check=True)
        state['compiledFiles'] = {path.name: digest(path) for path in output.iterdir()
                                  if path.suffix in ('.c', '.i', '.s', '.obj', '.exe')}
        state['status'] = 'prepared'
        save()
        if not args.build_only:
            state['status'] = 'running'
            save()
            command = [pwsh, '-NoProfile', '-File', str(BENCHMARK_TOOLS / 'run-native-fixture.ps1'),
                       '-GameRoot', str(candidate), '-OutputRoot', str(output),
                       '-ExpectedResultPrefix', 'PASS 11076 ', '-ToolRoot', str(tool_root),
                       '-TimeoutSeconds', str(args.timeout)]
            process = subprocess.Popen(command)
            try:
                code = process.wait(timeout=args.timeout + 120)
            except BaseException:
                subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
                process.wait()
                raise
            if code:
                raise RuntimeError('Native fixture failed; retained generated sources, binary and runtime')
            state['status'] = 'PASS'
            state['executionSha256'] = digest(output / 'execution.json')
    except BaseException as error:
        state['status'] = 'failed'
        state['error'] = str(error)
        raise
    finally:
        save()
    return state


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--reference-root', required=True, type=Path)
    parser.add_argument('--game-root', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--tool-root', type=Path)
    parser.add_argument('--timeout', type=int, default=600)
    parser.add_argument('--build-only', action='store_true')
    result = verify(parser.parse_args())
    print(result['status'])
