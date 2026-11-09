/* Differential SV_Move initialization cases with native helper stubs. */
/* ABI headers require the Quake types declared by quakedef.h. */
/* clang-format off */
#include "quakedef.h"
#include "asm_cliplinks.h"
#include "asm_clipmovetoentity.h"
/* clang-format on */
#include <string.h>

server_t sv;
areanode_t sv_areanodes[1];
static edict_t entities[3];
static vec3_t begin, finish, mins, maxs;
static trace_t initial;
static moveclip_t observed;
static unsigned mode, errors, helper_calls, checks;
trace_t SV_MoveControl(vec3_t, vec3_t, vec3_t, vec3_t, int, edict_t *);
trace_t SV_MoveCandidate(vec3_t, vec3_t, vec3_t, vec3_t, int, edict_t *);

trace_t SV_ClipMoveToEntity(edict_t *ent, vec3_t start, vec3_t low, vec3_t high,
                            vec3_t end) {
  if (ent != entities || start != begin || end != finish || low != mins ||
      high != maxs)
    errors++;
  helper_calls++;
  return initial;
}
void SV_ClipToLinks(areanode_t *node, moveclip_t *clip) {
  if (node != sv_areanodes)
    errors++;
  memcpy(&observed, clip, sizeof(observed));
  helper_calls++;
  if (mode) {
    clip->trace.startsolid = 1;
    clip->trace.fraction = .125f;
    clip->trace.endpos[0] = 123.5f;
    clip->trace.ent = entities + 2;
  }
}

static void __attribute__((noinline)) poison(unsigned byte_value) {
  volatile unsigned char bytes[2048];
  unsigned i;
  for (i = 0; i < sizeof(bytes); i++)
    bytes[i] = (unsigned char)byte_value;
}
typedef struct {
  moveclip_t clip;
  trace_t result;
  unsigned short cw, top, tag;
  unsigned errors, calls;
} snapshot_t;
static snapshot_t control, candidate;
static void
capture(snapshot_t *out,
        trace_t (*fn)(vec3_t, vec3_t, vec3_t, vec3_t, int, edict_t *), int type,
        edict_t *passed, unsigned short cw, unsigned byte_value) {
  unsigned short status, env[14];
  memset(out, 0, sizeof(*out));
  errors = helper_calls = 0;
  __asm__ __volatile__("fninit; fldcw %0" ::"m"(cw) : "memory");
  poison(byte_value);
  out->result = fn(begin, mins, maxs, finish, type, passed);
  memcpy(&out->clip, &observed, sizeof(observed));
  __asm__ __volatile__("fnstcw %0; fnstsw %1"
                       : "=m"(out->cw), "=m"(status)::"memory");
  out->top = status & 0x3800;
  __asm__ __volatile__("fnstenv %0; fldenv %0" : "=m"(env)::"memory");
  out->tag = env[4];
  out->errors = errors;
  out->calls = helper_calls;
}
int main(void) {
  static const int precision[] = {0, 0x200, 0x300};
  static const unsigned bits[] = {0, 0x80000000, 0x3f800000, 0xbf800000,
                                  1, 0x80000001, 0x7f800000, 0x7fc01234};
  unsigned seed, i, p, r, type, passed, ok = 1;
  unsigned short original, cw;
  FILE *report;
  sv.edicts = entities;
  __asm__ __volatile__("fnstcw %0" : "=m"(original));
  for (p = 0; p < 3 && ok; p++)
    for (r = 0; r < 4 && ok; r++) {
      cw = (original & ~0xf00) | precision[p] | (r << 10);
      for (seed = 0; seed < 128 && ok; seed++)
        for (type = 0; type < 3 && ok; type++)
          for (passed = 0; passed < 2 && ok; passed++)
            for (mode = 0; mode < 2 && ok; mode++) {
              for (i = 0; i < 3; i++) {
                begin[i] = (int)(seed * 13 + i * 7) - 200;
                finish[i] = begin[i] + ((int)(seed % 11) - 5) * .125f;
                mins[i] = -(float)(seed % 19 + i);
                maxs[i] = (float)(seed % 17 + i);
              }
              if (seed % 16 < 8)
                memcpy(&begin[seed % 3], bits + seed % 8, 4);
              if (seed % 13 == 0)
                memcpy(&finish[(seed + 1) % 3], bits + (seed + 3) % 8, 4);
              memset(&initial, 0, sizeof(initial));
              initial.allsolid = seed & 1;
              initial.startsolid = (seed >> 1) & 1;
              initial.inopen = (seed >> 2) & 1;
              initial.inwater = (seed >> 3) & 1;
              initial.fraction = (seed % 5) * .25f;
              initial.ent = entities + seed % 3;
              for (i = 0; i < 3; i++) {
                initial.endpos[i] = i + seed * .125f;
                initial.plane.normal[i] = (int)(seed + i) - 64;
              }
              initial.plane.dist = seed * .0625f;
              capture(&control, SV_MoveControl, type,
                      passed ? entities + 1 : NULL, cw, 0xa5);
              capture(&candidate, SV_MoveCandidate, type,
                      passed ? entities + 1 : NULL, cw, 0x5a);
              checks++;
              if (memcmp(&control, &candidate, sizeof(control)) ||
                  control.errors || control.calls != 2 || control.cw != cw ||
                  control.top || control.tag != 0xffff) {
                for (i = 0; i < sizeof(control); i++)
                  if (((byte *)&control)[i] != ((byte *)&candidate)[i])
                    break;
                printf("FAIL seed=%u type=%u passed=%u mode=%u cw=%x byte=%u "
                       "errors=%u calls=%u\n",
                       seed, type, passed, mode, cw, i, control.errors,
                       control.calls);
                ok = 0;
              }
            }
    }
  __asm__ __volatile__("fninit; fldcw %0" ::"m"(original) : "memory");
  report = fopen("RESULT.TXT", "w");
  if (!report)
    return 2;
  fprintf(
      report,
      "%s %u move-initialization cases; exact 124-byte clip and returned "
      "trace; modes, bounds, passedict, poisoned stack and 12 x87 settings\n",
      ok ? "PASS" : "FAIL", checks);
  fclose(report);
  return ok ? 0 : 1;
}
