/* Small DOS text launcher for the NitroQuake benchmark disc. */
#include <conio.h>
#include <dpmi.h>
#include <errno.h>
#include <fcntl.h>
#include <io.h>
#include <process.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define DRIVE_COUNT 26
#define PATH_CAP 64
#define RUN_WAIT 0

typedef struct {
	const char *title;
	const char *exe;
	const char *log_stem;
} engine_t;

static const engine_t engines[3] = {
	{ "NitroQuake", "NQ.EXE", "NQDEM" },
	{ "486Quake", "Q486.EXE", "Q486D" },
	{ "Original Quake", "QUAKE.EXE", "QUAKE" }
};

/* Rotate the first engine by demo so each variant gets a warm-start share. */
static const int demo_order[3][3] = {
	{ 0, 1, 2 },
	{ 1, 2, 0 },
	{ 2, 0, 1 }
};

static char disc_root[PATH_CAP];
static char data_root[PATH_CAP];
static int disc_drive = -1;
static int data_drive = -1;

static int copy_file(const char *source_path, const char *destination_path);

static int file_exists(const char *path)
{
	FILE *file = fopen(path, "rb");
	if (!file)
		return 0;
	fclose(file);
	return 1;
}

static void path_join(char *out, size_t capacity, const char *root,
					  const char *leaf)
{
	size_t root_length = strlen(root);
	size_t leaf_length = strlen(leaf);
	if (root_length + leaf_length + 2 > capacity) {
		if (capacity)
			out[0] = '\0';
		return;
	}
	memcpy(out, root, root_length);
	out[root_length] = '\\';
	memcpy(out + root_length + 1, leaf, leaf_length + 1);
}

static int path_is_directory(const char *path)
{
	struct stat info;
	return stat(path, &info) == 0 && S_ISDIR(info.st_mode);
}

static int ensure_directory(const char *path)
{
	if (path_is_directory(path))
		return 1;
	if (mkdir(path, 0777) == 0)
		return 1;
	return errno == EEXIST && path_is_directory(path);
}

static int current_drive(void)
{
	__dpmi_regs regs;
	memset(&regs, 0, sizeof(regs));
	regs.h.ah = 0x19;
	__dpmi_int(0x21, &regs);
	return regs.h.al;
}

static int is_cd_drive(int drive)
{
	__dpmi_regs regs;
	memset(&regs, 0, sizeof(regs));
	regs.x.ax = 0x150b;
	regs.x.cx = (unsigned short)drive;
	__dpmi_int(0x2f, &regs);
	return regs.x.ax != 0 && regs.x.bx == 0xadad;
}

static int is_fixed_local_drive(int drive)
{
	__dpmi_regs regs;
	memset(&regs, 0, sizeof(regs));
	regs.x.ax = 0x4408;
	regs.h.bl = (unsigned char)(drive + 1);
	__dpmi_int(0x21, &regs);
	if ((regs.x.flags & 1) || regs.x.ax != 1)
		return 0;

	memset(&regs, 0, sizeof(regs));
	regs.x.ax = 0x4409;
	regs.h.bl = (unsigned char)(drive + 1);
	__dpmi_int(0x21, &regs);
	if (!(regs.x.flags & 1) && (regs.x.dx & 0x1000))
		return 0;
	return 1;
}

static int test_disc_drive(int drive)
{
	char marker[PATH_CAP];
	if (drive < 0 || drive >= DRIVE_COUNT)
		return 0;
	snprintf(disc_root, sizeof(disc_root), "%c:\\NQ", 'A' + drive);
	path_join(marker, sizeof(marker), disc_root, "NQ.ID");
	if (!file_exists(marker))
		return 0;
	disc_drive = drive;
	return 1;
}

static int read_disc_hint(int drive)
{
	char hint_path[PATH_CAP];
	FILE *file;
	int letter;
	if (drive < 0 || drive >= DRIVE_COUNT)
		return 0;
	snprintf(hint_path, sizeof(hint_path), "%c:\\NQDATA\\DISC.TXT",
			 'A' + drive);
	file = fopen(hint_path, "rb");
	if (!file)
		return 0;
	letter = fgetc(file);
	fclose(file);
	if (letter >= 'a' && letter <= 'z')
		letter -= 'a' - 'A';
	return letter >= 'A' && letter <= 'Z' && test_disc_drive(letter - 'A');
}

static int find_disc(void)
{
	int drive;
	int preferred = current_drive();
	if (test_disc_drive(preferred))
		return 1;
	/* PREP records the discovered CD before switching to writable storage. */
	if (read_disc_hint(preferred))
		return 1;
	for (drive = 0; drive < DRIVE_COUNT; ++drive) {
		if (is_cd_drive(drive) && test_disc_drive(drive))
			return 1;
	}
	return 0;
}

static int writable_probe(const char *root)
{
	char probe[PATH_CAP];
	unsigned int attempt;
	for (attempt = 0; attempt < 1000; ++attempt) {
		int handle;
		char leaf[16];
		snprintf(leaf, sizeof(leaf), "W%04u.TMP", attempt);
		path_join(probe, sizeof(probe), root, leaf);
		handle = open(probe, O_WRONLY | O_CREAT | O_EXCL | O_BINARY,
					  S_IREAD | S_IWRITE);
		if (handle >= 0) {
			close(handle);
			unlink(probe);
			return 1;
		}
		if (errno != EEXIST)
			return 0;
	}
	return 0;
}

static int find_data_drive(void)
{
	int order[DRIVE_COUNT];
	int count = 0;
	int drive;
	int preferred = current_drive();
	char candidate[PATH_CAP];

	if (preferred >= 0 && preferred < DRIVE_COUNT)
		order[count++] = preferred;
	for (drive = 0; drive < DRIVE_COUNT; ++drive) {
		if (drive != preferred)
			order[count++] = drive;
	}

	for (drive = 0; drive < count; ++drive) {
		int index = order[drive];
		if (!is_fixed_local_drive(index) || is_cd_drive(index))
			continue;
		snprintf(candidate, sizeof(candidate), "%c:\\NQDATA", 'A' + index);
		if (!ensure_directory(candidate) || !writable_probe(candidate))
			continue;
		strcpy(data_root, candidate);
		data_drive = index;
		return 1;
	}
	return 0;
}

static int select_drive_directory(int drive, const char *directory)
{
	__dpmi_regs regs;
	memset(&regs, 0, sizeof(regs));
	regs.h.ah = 0x0e;
	regs.h.dl = (unsigned char)drive;
	__dpmi_int(0x21, &regs);
	return chdir(directory) == 0;
}

static int activate_disc(void)
{
	return disc_drive >= 0 && select_drive_directory(disc_drive, "\\NQ");
}

static int make_layout(void)
{
	char path[PATH_CAP];
	char source[PATH_CAP];
	const char *directories[] = { "PLAY", "PLAY\\ID1", "BENCH",
								   "BENCH\\ID1", "LOGS" };
	unsigned int i;
	if (!ensure_directory(data_root))
		return 0;
	for (i = 0; i < sizeof(directories) / sizeof(directories[0]); ++i) {
		path_join(path, sizeof(path), data_root, directories[i]);
		if (!ensure_directory(path))
			return 0;
	}
	path_join(source, sizeof(source), data_root, "CWSDPMI.EXE");
	path_join(path, sizeof(path), data_root, "PLAY\\CWSDPMI.EXE");
	if (!copy_file(source, path))
		return 0;
	path_join(path, sizeof(path), data_root, "BENCH\\CWSDPMI.EXE");
	if (!copy_file(source, path))
		return 0;
	return 1;
}

static int write_text(const char *path, const char *text)
{
	FILE *file = fopen(path, "wb");
	int ok;
	if (!file)
		return 0;
	ok = fputs(text, file) >= 0;
	if (fclose(file) != 0)
		ok = 0;
	return ok;
}

static int copy_file(const char *source_path, const char *destination_path)
{
	FILE *source = fopen(source_path, "rb");
	FILE *destination;
	unsigned char buffer[4096];
	size_t count;
	int ok = 1;
	if (!source)
		return 0;
	destination = fopen(destination_path, "wb");
	if (!destination) {
		fclose(source);
		return 0;
	}
	while ((count = fread(buffer, 1, sizeof(buffer), source)) != 0) {
		if (fwrite(buffer, 1, count, destination) != count) {
			ok = 0;
			break;
		}
	}
	if (ferror(source))
		ok = 0;
	if (fclose(destination) != 0)
		ok = 0;
	fclose(source);
	return ok;
}

static int write_if_missing(const char *path, const char *text)
{
	if (file_exists(path))
		return 1;
	return write_text(path, text);
}

static int prepare_play_files(char *play_root, size_t root_size,
							 char *play_id1, size_t id1_size)
{
	char path[PATH_CAP];
	strncpy(play_root, data_root, root_size - 1);
	play_root[root_size - 1] = '\0';
	strncat(play_root, "\\PLAY", root_size - strlen(play_root) - 1);
	path_join(play_id1, id1_size, play_root, "ID1");
	path_join(path, sizeof(path), play_id1, "CONFIG.CFG");
	return write_if_missing(path, "vid_mode 0\nviewsize 100\n");
}

static int prepare_bench_files(int demo, char *bench_root, size_t root_size,
							  char *bench_id1, size_t id1_size)
{
	char path[PATH_CAP];
	char demo_config[64];
	strncpy(bench_root, data_root, root_size - 1);
	bench_root[root_size - 1] = '\0';
	strncat(bench_root, "\\BENCH", root_size - strlen(bench_root) - 1);
	path_join(bench_id1, id1_size, bench_root, "ID1");
	path_join(path, sizeof(path), bench_id1, "CONFIG.CFG");
	if (!write_text(path, "vid_mode 0\nviewsize 100\n"))
		return 0;
	snprintf(demo_config, sizeof(demo_config),
			 "viewsize 100\ntimedemo demo%d\n", demo);
	path_join(path, sizeof(path), bench_id1, "BENCH.CFG");
	if (!write_text(path, demo_config))
		return 0;
	path_join(path, sizeof(path), bench_id1, "QCONSOLE.LOG");
	remove(path);
	return 1;
}

static int create_session(char *session, size_t capacity)
{
	char logs[PATH_CAP];
	unsigned int number;
	path_join(logs, sizeof(logs), data_root, "LOGS");
	if (!ensure_directory(logs))
		return 0;
	for (number = 1; number < 10000; ++number) {
		char leaf[12];
		snprintf(leaf, sizeof(leaf), "RUN%04u", number);
		path_join(session, capacity, logs, leaf);
		if (mkdir(session, 0777) == 0)
			return 1;
		if (errno != EEXIST)
			return 0;
	}
	return 0;
}

static const char *log_name(int engine, int demo)
{
	static char name[16];
	snprintf(name, sizeof(name), "%s%d.LOG", engines[engine].log_stem, demo);
	return name;
}

static void save_console_log(const char *bench_id1, const char *session,
							 int engine, int demo)
{
	char source[PATH_CAP];
	char destination[PATH_CAP];
	path_join(source, sizeof(source), bench_id1, "QCONSOLE.LOG");
	if (!file_exists(source)) {
		cprintf("  No QCONSOLE.LOG was produced.\r\n");
		return;
	}
	path_join(destination, sizeof(destination), session, log_name(engine, demo));
	if (copy_file(source, destination))
		cprintf("  Saved log: %s\r\n", destination);
	else
		cprintf("  Could not save log: %s\r\n", destination);
}

static int command_tail_length(char **argv)
{
	int length = 0;
	int index;
	for (index = 1; argv[index]; ++index)
		length += (int)strlen(argv[index]) + 1;
	return length ? length - 1 : 0;
}

static int launch_engine(int engine, int demo, const char *session)
{
	char engine_exe[PATH_CAP];
	char play_root[PATH_CAP];
	char play_id1[PATH_CAP];
	char bench_root[PATH_CAP];
	char bench_id1[PATH_CAP];
	char *play_argv[] = { engine_exe,
		"-basedir", play_root, "-stdvid", "-nosound", "-nocdaudio", "-path",
		"pak0.pak", "pak1.pak", play_id1, NULL };
	char *bench_argv[] = { engine_exe,
		"-basedir", bench_root, "-stdvid", "-nosound", "-nocdaudio", "-condebug", "-path",
		"pak0.pak", "pak1.pak", bench_id1,
		"+exec", "BENCH.CFG", NULL };
	int status;

	if (engine < 0 || engine > 2)
		return -1;
	if (data_drive < 0 || !select_drive_directory(data_drive,
			 demo == 0 ? "\\NQDATA\\PLAY" : "\\NQDATA\\BENCH")) {
		cprintf("Could not activate the writable game directory.\r\n");
		return -1;
	}
	path_join(engine_exe, sizeof(engine_exe), data_root, engines[engine].exe);
	if (demo == 0) {
		if (!prepare_play_files(play_root, sizeof(play_root),
								play_id1, sizeof(play_id1))) {
			cprintf("Could not prepare the writable play directory.\r\n");
			return -1;
		}
		if (!select_drive_directory(disc_drive, "\\NQ\\ID1")) {
			cprintf("Could not return to the game disc.\r\n");
			return -1;
		}
		if (command_tail_length(play_argv) > 125) {
			cprintf("DOS command tail is too long for this path.\r\n");
			return -1;
		}
		cprintf("Starting %s in standard VGA 320x200 mode...\r\n",
				engines[engine].title);
		status = spawnv(RUN_WAIT, engine_exe, play_argv);
	} else {
		char log_dir[PATH_CAP];
		if (!prepare_bench_files(demo, bench_root, sizeof(bench_root),
								 bench_id1, sizeof(bench_id1))) {
			cprintf("Could not prepare the benchmark profile.\r\n");
			return -1;
		}
		if (command_tail_length(bench_argv) > 125) {
			cprintf("DOS command tail is too long for this path.\r\n");
			return -1;
		}
		if (!select_drive_directory(disc_drive, "\\NQ\\ID1")) {
			cprintf("Could not return to the game disc.\r\n");
			return -1;
		}
		cprintf("\r\n%s / demo%d\r\n", engines[engine].title, demo);
		cprintf("When timedemo playback ends, press ~, type QUIT, then Enter.\r\n");
		status = spawnv(RUN_WAIT, engine_exe, bench_argv);
		select_drive_directory(data_drive, "\\NQDATA");
		path_join(log_dir, sizeof(log_dir), data_root, "BENCH\\ID1");
		save_console_log(log_dir, session, engine, demo);
	}
	select_drive_directory(data_drive, "\\NQDATA");
	if (status < 0)
		cprintf("Could not start %s (DOS error %d).\r\n", engines[engine].title, errno);
	return status;
}

static void wait_for_key(void)
{
	cprintf("\r\nPress any key to continue...");
	(void)getch();
}

static int run_benchmarks(int demo)
{
	char session[PATH_CAP];
	int first_demo = demo ? demo : 1;
	int last_demo = demo ? demo : 3;
	int current_demo;
	int run_number = 0;

	if (!create_session(session, sizeof(session))) {
		cprintf("Could not create a new benchmark log session.\r\n");
		return 0;
	}
	cprintf("Benchmark output: %s\r\n", session);
	cprintf("All runs use VGA 320x200, viewsize 100, and disabled audio.\r\n");

	for (current_demo = first_demo; current_demo <= last_demo; ++current_demo) {
		int order_index = current_demo - 1;
		int position;
		for (position = 0; position < 3; ++position) {
			int engine = demo_order[order_index][position];
			int status = launch_engine(engine, current_demo, session);
			++run_number;
			if (status < 0)
				cprintf("Run ended with an error.\r\n");
			if (current_demo != last_demo || position != 2) {
				int key;
				cprintf("\r\nPress a key for the next run, or Esc to stop.");
				key = getch();
				if (key == 27) {
					cprintf("\r\nStopped after %d run(s).\r\n", run_number);
					cprintf("Saved files remain in %s.\r\n", session);
					return 1;
				}
			}
		}
	}
	cprintf("\r\nBenchmark batch complete.\r\n");
	cprintf("Logs: %s\r\n", session);
	return 1;
}

static int launch_one(int engine)
{
	int status = launch_engine(engine, 0, NULL);
	if (status >= 0)
		cprintf("\r\n%s returned to DOS.\r\n", engines[engine].title);
	return status >= 0;
}

static void write_probe_report(void)
{
	char path[PATH_CAP];
	FILE *file;
	path_join(path, sizeof(path), data_root, "PROBE.TXT");
	file = fopen(path, "wb");
	if (!file) {
		cprintf("Could not write %s\r\n", path);
		return;
	}
	fprintf(file, "NitroQuake DOS launcher path probe\r\n");
	fprintf(file, "Disc: %s\r\n", disc_root);
	fprintf(file, "Output: %s\r\n", data_root);
	fclose(file);
	cprintf("Disc found: %s\r\n", disc_root);
	cprintf("Writable output: %s\r\n", data_root);
	cprintf("Path report: %s\r\n", path);
}

static int equal_arg(const char *left, const char *right)
{
	while (*left && *right) {
		char a = *left;
		char b = *right;
		if (a >= 'a' && a <= 'z') a -= 'a' - 'A';
		if (b >= 'a' && b <= 'z') b -= 'a' - 'A';
		if (a != b)
			return 0;
		++left;
		++right;
	}
	return *left == *right;
}

static int run_argument(const char *argument)
{
	if (equal_arg(argument, "/PROBE")) {
		write_probe_report();
		return 1;
	}
	if (equal_arg(argument, "/NQ") || equal_arg(argument, "/RUNNQ"))
		return launch_one(0);
	if (equal_arg(argument, "/486") || equal_arg(argument, "/RUN486"))
		return launch_one(1);
	if (equal_arg(argument, "/QUAKE") || equal_arg(argument, "/RUNQUAKE"))
		return launch_one(2);
	if (equal_arg(argument, "/D1") || equal_arg(argument, "/DEMO1"))
		return run_benchmarks(1);
	if (equal_arg(argument, "/D2") || equal_arg(argument, "/DEMO2"))
		return run_benchmarks(2);
	if (equal_arg(argument, "/D3") || equal_arg(argument, "/DEMO3"))
		return run_benchmarks(3);
	if (equal_arg(argument, "/ALL") || equal_arg(argument, "/ALLDEMO"))
		return run_benchmarks(0);
	return -1;
}

static void draw_menu(int selection)
{
	static const char *items[] = {
		"Launch NitroQuake",
		"Launch 486Quake",
		"Launch original Quake",
		"Benchmark demo1 on all engines",
		"Benchmark demo2 on all engines",
		"Benchmark demo3 on all engines",
		"Run full nine-case benchmark",
		"Exit to DOS"
	};
	int i;
	clrscr();
	textcolor(LIGHTCYAN);
	cprintf("NITROQUAKE DOS LAUNCHER\r\n");
	textcolor(WHITE);
	cprintf("Portable CD benchmark menu  |  VGA software 320x200\r\n\r\n");
	cprintf("Disc:   %s\r\n", disc_root);
	cprintf("Output: %s\r\n\r\n", data_root);
	for (i = 0; i < 8; ++i) {
		if (i == selection) {
			textcolor(YELLOW);
			cprintf(" > %d. %s\r\n", i + 1, items[i]);
		} else {
			textcolor(WHITE);
			cprintf("   %d. %s\r\n", i + 1, items[i]);
		}
	}
	textcolor(LIGHTGRAY);
	cprintf("\r\nUse Up/Down and Enter, or press a number. Esc exits.\r\n");
	textcolor(WHITE);
}

static int interactive_menu(void)
{
	int selection = 0;
	for (;;) {
		int key;
		draw_menu(selection);
		key = getch();
		if (key == 0 || key == 0xe0) {
			key = getch();
			if (key == 72 && selection > 0)
				--selection;
			else if (key == 80 && selection < 7)
				++selection;
			continue;
		}
		if (key == 27)
			return 0;
		if (key >= '1' && key <= '8')
			selection = key - '1';
		else if (key != 13)
			continue;
		if (key == '1' || (key == 13 && selection == 0)) {
			launch_one(0);
			wait_for_key();
		} else if (key == '2' || (key == 13 && selection == 1)) {
			launch_one(1);
			wait_for_key();
		} else if (key == '3' || (key == 13 && selection == 2)) {
			launch_one(2);
			wait_for_key();
		} else if (key == '4' || (key == 13 && selection == 3)) {
			run_benchmarks(1);
			wait_for_key();
		} else if (key == '5' || (key == 13 && selection == 4)) {
			run_benchmarks(2);
			wait_for_key();
		} else if (key == '6' || (key == 13 && selection == 5)) {
			run_benchmarks(3);
			wait_for_key();
		} else if (key == '7' || (key == 13 && selection == 6)) {
			run_benchmarks(0);
			wait_for_key();
		} else if (key == '8' || (key == 13 && selection == 7)) {
			return 0;
		}
	}
}

int main(int argc, char **argv)
{
	int i;
	if (!find_disc()) {
		cprintf("NitroQuake disc not found. Insert it and start from NQ\\START.BAT.\r\n");
		return 2;
	}
	if (!find_data_drive()) {
		cprintf("No writable local fixed disk was found.\r\n");
		cprintf("The CD is read-only; connect a writable hard disk and retry.\r\n");
		return 3;
	}
	if (!make_layout()) {
		cprintf("Could not prepare the writable NQDATA directories.\r\n");
		return 4;
	}
	if (!activate_disc()) {
		cprintf("Could not set the game disc as the current DOS directory.\r\n");
		return 5;
	}
	for (i = 1; i < argc; ++i) {
		int result = run_argument(argv[i]);
		if (result >= 0)
			return result ? 0 : 1;
	}
	if (argc > 1) {
		cprintf("Usage: NQMENU [/NQ|/486|/QUAKE|/D1|/D2|/D3|/ALL|/PROBE]\r\n");
		return 6;
	}
	return interactive_menu() ? 1 : 0;
}
