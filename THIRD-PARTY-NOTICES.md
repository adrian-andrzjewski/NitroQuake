# Third-party notices

## Quake

The engine source is derived from id Software's Quake GPL source release.
Original copyright and license notices are retained in the engine source, along
with the upstream `gnu.txt` and `readme.txt`. Quake's game data and branded
graphics are separate copyrighted material and are not included in either
NitroQuake repository. See the [upstream source release](https://github.com/id-Software/Quake)
and [engine license](https://github.com/adrian-andrzjewski/NitroQuake-engine/blob/main/LICENSE).

## Build and benchmark tools

The build bootstrap downloads DJGPP components from their upstream distribution
sites and records pinned source URLs and hashes in the engine repository. The
benchmark workflow may use DOSBox-X installed by the user. Neither toolchain
archives nor DOSBox-X binaries are vendored here; each remains subject to its
own copyright and license terms.

The benchmark suite does not include the HX/HDPMI runtime. Its documentation
identifies the upstream package for users who independently choose that optional
DPMI host; the runtime and its vendor documentation must be obtained and used
under the upstream terms.

## Project-owned material

The NitroQuake banner and logo files in `docs/assets/branding/` are project
branding artwork cleared by the project owner for public distribution with this
repository. They are separate from Quake game data. This clearance does not
grant rights to use id Software trademarks outside this independent project.
First-party source, tools, and documentation are covered by the repository
license unless a file carries a different notice.
