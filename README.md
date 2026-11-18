# NitroQuake

<p align="center">
  <img src="docs/assets/branding/nitroquake-banner.svg" alt="Original Quake. The 486, pushed further. NitroQuake DOS performance project." width="100%">
</p>

<p align="center">
  <img src="docs/assets/branding/NitroQuakeLogo-inv.png#gh-light-mode-only" alt="NitroQuake logo" width="320">
  <img src="docs/assets/branding/NitroQuakeLogo.png#gh-dark-mode-only" alt="NitroQuake logo" width="320">
</p>

NitroQuake is an independent performance engineering project for id Software's
Quake MS-DOS software renderer. It focuses on measured, behavior-preserving
optimizations for 486-class PCs with x87 floating-point hardware.

The source and benchmark suite are maintained in separate Git repositories.
The engine repository contains the Quake-derived DOS source; this repository
contains the benchmark automation, fixtures, and project documentation. The
workspace bootstrap checks out the exact engine revision recorded in
`engine.lock`.

## Build

```powershell
git clone https://github.com/adrian-andrzjewski/NitroQuake.git
Set-Location NitroQuake
pwsh -NoProfile -File .\benchmarks\tools\bootstrap-workspace.ps1
Set-Location .\quake
pwsh -NoProfile -File tools\bootstrap-dos.ps1
pwsh -NoProfile -File tools\build-dos.ps1 -Configuration i486-release
```

See the [engine build guide](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/BUILD-DOS.md)
and [benchmark guide](benchmarks/README.md) for prerequisites and validation
commands. The source build does not require game data.

## Quake game data

No Quake PAK files, maps, models, music, demos, or captured game imagery are
distributed here. To run the engine or gameplay benchmarks, provide a legally
obtained copy of Quake's registered `id1/pak0.pak` and `id1/pak1.pak` in the
runtime `id1/` directory. These files are ignored by Git. Do not commit or
redistribute commercial game data. The original source release distinguishes
the GPL-licensed engine source from the separately copyrighted game data.

Quake is a trademark of id Software. NitroQuake is an independent project and
is not affiliated with or endorsed by id Software.

## Project documents

- [Documentation index](docs/INDEX.md)
- [Current architecture and evidence limits](docs/architecture/current-state.md)
- [Repository boundaries](docs/repository-layout.md)
- [Benchmark suite guide](benchmarks/README.md)
- [Benchmark comparison](benchmarks/docs/BENCHMARK-COMPARISON.md)
- [Optimization history](benchmarks/docs/history/INDEX.md)
- [Distribution and licensing notes](THIRD-PARTY-NOTICES.md)

## License

Project source and tools are provided under GNU GPL version 2 or, at your
option, any later version, subject to the notices and license terms retained
with third-party material. See [LICENSE](LICENSE) and
[third-party notices](THIRD-PARTY-NOTICES.md).
