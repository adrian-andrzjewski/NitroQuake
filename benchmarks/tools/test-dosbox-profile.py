"""Pinned 486DX/x87 runtime contract, independent of the game compiler."""
import hashlib, os, re
from _workspace import BENCHMARK_ROOT
def fail(message):
    raise AssertionError(message)
def main():
    # The selected hardware contract is an 80486DX with its 387-compatible x87.
    # Keep the emulator profile and its timedemo hash pin aligned so the runtime
    # fixture cannot silently fall back to a 486SX/no-FPU configuration.
    dosbox_profile_path = os.path.join(str(BENCHMARK_ROOT), "tools", "dosbox-x-486-high.conf")
    try:
        with open(dosbox_profile_path, "rb") as handle:
            dosbox_profile_bytes = handle.read()
        dosbox_profile_text = dosbox_profile_bytes.decode("ascii").replace("\r\n", "\n")
        in_cpu_section = False
        cpu_options: dict[str, str] = {}
        for line in dosbox_profile_text.splitlines():
            stripped = line.strip()
            if stripped.startswith("[") and stripped.endswith("]"):
                in_cpu_section = stripped.lower() == "[cpu]"
            elif in_cpu_section and stripped and not stripped.startswith("#") and "=" in stripped:
                key, value = stripped.split("=", 1)
                cpu_options[key.strip().lower()] = value.strip().lower()
        if cpu_options.get("cputype") != "486":
            fail("the DOSBox-X compatibility profile must set cputype=486")
        if cpu_options.get("fpu") != "387":
            fail("the DOSBox-X compatibility profile must set fpu=387 for the 486DX x87 contract")

        profile_hash = hashlib.sha256(dosbox_profile_text.encode("ascii")).hexdigest().upper()
        with open(os.path.join(str(BENCHMARK_ROOT), "tools", "timedemo-dos.ps1"), "r", encoding="utf-8") as handle:
            timedemo_script = handle.read()
        hash_match = re.search(
            r"ExpectedProfileSha256\s*=\s*'([0-9A-Fa-f]{64})'", timedemo_script
        )
        if hash_match is None:
            fail("the timedemo DOSBox profile hash pin is missing or malformed")
        elif hash_match.group(1).upper() != profile_hash:
            fail(
                "the DOSBox-X 486 profile hash is %s, but timedemo-dos.ps1 pins %s"
                % (profile_hash, hash_match.group(1).upper())
            )
    except (OSError, UnicodeDecodeError) as error:
        fail("could not verify the DOSBox-X 486DX/x87 profile: %s" % error)

    print("PASS: pinned DOSBox 486DX/x87 profile")
if __name__ == '__main__': main()
