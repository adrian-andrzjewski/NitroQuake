"""Transferred runtime scenario and paired harness contracts."""
import json, os
from _workspace import BENCHMARK_ROOT
def fail(message): raise AssertionError(message)
def main():
    particle_scenario_path = os.path.join(str(BENCHMARK_ROOT), "tools", "render-scenarios-runparticleeffect.json")
    if not os.path.isfile(particle_scenario_path):
        fail("the exact R_RunParticleEffect event scenario manifest is missing")
    else:
        try:
            with open(particle_scenario_path, "r", encoding="utf-8") as handle:
                particle_scenario_manifest = json.load(handle)
            particle_scenarios = particle_scenario_manifest.get("scenarios", [])
            if len(particle_scenarios) != 1:
                fail("the R_RunParticleEffect event scenario manifest must contain exactly one scenario")
            else:
                scene = particle_scenarios[0]
                exact_tolerance = {"channel": 0, "maxChangedPixelFraction": 0, "maxMeanAbsoluteError": 0}
                if scene.get("id") != "demo2-wizspike-event":
                    fail("the D_DrawParticle parity scenario is not the known demo2 particle event")
                if "R_RunParticleEffect" not in scene.get("description", ""):
                    fail("the D_DrawParticle parity scenario does not route its event through R_RunParticleEffect")
                if scene.get("requiredBenchEvents") != ["runParticleEffect"]:
                    fail("the D_DrawParticle parity scenario does not require the R_RunParticleEffect event")
                if scene.get("expectedBenchEventFrames") != {"runParticleEffect": [10]}:
                    fail("the D_DrawParticle parity scenario does not pin its particle event to frame 10")
                if scene.get("expectedFrames") != 10 or scene.get("captureFrame") != 10:
                    fail("the D_DrawParticle parity scenario no longer captures the exact 10-frame event")
                if scene.get("tolerance") != exact_tolerance:
                    fail("the D_DrawParticle event scenario is no longer an exact pixel comparison")
        except (OSError, json.JSONDecodeError) as error:
            fail("could not read the D_DrawParticle event scenario manifest: %s" % error)

    parity_source_path = os.path.join(str(BENCHMARK_ROOT), "tools", "render-parity-dos.ps1")
    try:
        with open(parity_source_path, "r", encoding="utf-8") as handle:
            parity_source = handle.read()
        if "[string]$ScenarioFile" not in parity_source or "'-ScenarioFile', $pairScenarioFile" not in parity_source:
            fail("the paired render harness does not accept and forward the exact event scenario file")
    except OSError as error:
        fail("could not read the paired render harness source: %s" % error)

    print('PASS: exact particle-event scenario and paired runner')
if __name__ == '__main__': main()
