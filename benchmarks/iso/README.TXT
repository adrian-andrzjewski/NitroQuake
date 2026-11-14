NITROQUAKE DOS BENCHMARK DISC
==============================

NON-BOOTABLE ISO-9660 DISC. Boot MS-DOS and load a CD-ROM driver first.
At the DOS prompt, switch to the letter assigned to this CD, then type:

  CD \
  START

You can also type CD \NQ and START from the NQ directory.

The launcher finds this disc and a writable local hard disk automatically.
It never writes to the CD. Configurations and benchmark logs go under
\NQDATA on the selected writable disk. The launcher prints the full path.

MENU
  Use Up/Down and Enter. Number keys are shortcuts; Esc returns to DOS.
  NitroQuake, 486Quake, and original Quake can be launched individually.
  Benchmark Demo 1, Demo 2, or Demo 3 runs that demo on all three engines.
  Full Benchmark runs all nine combinations in a rotated order.

Each benchmark uses the same PAK files, standard VGA 320x200 mode, viewsize
100, and disabled game and CD audio. The menu tells you when a timedemo
finishes. In the game, press ~, type QUIT, and press Enter to return to the
menu. Logs are preserved in a new directory under \NQDATA\LOGS for every
benchmark session.

DIRECT COMMANDS (RUN FROM \NQ)
  RUNNQ       Launch NitroQuake
  RUN486      Launch 486Quake
  RUNQUAKE    Launch original Quake
  DEMO1       Run demo1 on all three engines
  DEMO2       Run demo2 on all three engines
  DEMO3       Run demo3 on all three engines
  ALLDEMO     Run all nine combinations

Run NQPREP.COM /PROBE to write a small path report to \NQDATA\PROBE.TXT.
If no writable local disk is available, connect one and run START again.
The disc is non-bootable; no DOSBox commands or configuration files are needed.

Use legally obtained Quake PAK files. Their copyright remains with the owners.
