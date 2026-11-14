/* Differential collision traversal cases with native helper stubs. */
/* ABI headers require the Quake types declared by quakedef.h. */
/* clang-format off */
#include "quakedef.h"
#include "collision/asm_cliplinks.h"
#include "collision/asm_clipmovetoentity.h"
/* clang-format on */
#include <setjmp.h>
#include <string.h>

server_t sv;
unsigned bench486_cliptolinks_asm_calls;
static edict_t entities[67];
static areanode_t nodes[65];
static vec3_t begin, finish, mins, maxs;
static moveclip_t initial, clip;
static unsigned seed_value, helper_count, errors, error_kind, checks;
static char error_message[128];
static jmp_buf error_jump;
typedef struct {
  int entity;
  unsigned low[3], high[3];
} helper_log_t;
static helper_log_t log_entries[256];
void SV_ClipToLinksControl(areanode_t *, moveclip_t *);
void SV_ClipToLinksCandidate(areanode_t *, moveclip_t *);
int CallClipWithAbi(void (*fn)(areanode_t *, moveclip_t *), areanode_t *,
                    moveclip_t *);

void Sys_Error(char *message, ...) {
  error_kind = 1;
  strncpy(error_message, message, sizeof(error_message) - 1);
  longjmp(error_jump, 1);
}
trace_t SV_ClipMoveToEntity(edict_t *ent, vec3_t start, vec3_t low, vec3_t high,
                            vec3_t end) {
  trace_t result;
  unsigned index = (unsigned)(ent - entities), i;
  if (index >= 67 || start != begin || end != finish || helper_count >= 256) {
    errors++;
    Sys_Error("fixture helper arguments");
  }
  log_entries[helper_count].entity = index;
  memcpy(log_entries[helper_count].low, low, 12);
  memcpy(log_entries[helper_count].high, high, 12);
  helper_count++;
  memset(&result, 0, sizeof(result));
  result.fraction = ((index * 3 + helper_count + seed_value) % 9) * .125f;
  result.allsolid = (seed_value % 17 == 0 && helper_count == 2);
  result.startsolid = (seed_value % 11 == 0 && helper_count == 1);
  result.inopen = 1;
  result.inwater = seed_value & 1;
  result.ent = entities;
  for (i = 0; i < 3; i++) {
    result.endpos[i] = (int)index - (int)i;
    result.plane.normal[i] = i * .125f;
  }
  result.plane.dist = index * .25f;
  return result;
}
static void setup(unsigned seed, unsigned shape) {
  unsigned i, count = shape ? 65 : 31;
  memset(entities, 0, sizeof(entities));
  memset(nodes, 0, sizeof(nodes));
  memset(&initial, 0, sizeof(initial));
  sv.edicts = entities;
  for (i = 0; i < 67; i++) {
    entities[i].v.solid = SOLID_BBOX;
    entities[i].v.size[0] = 16;
    entities[i].v.absmin[0] = entities[i].v.absmin[1] =
        entities[i].v.absmin[2] = -64;
    entities[i].v.absmax[0] = entities[i].v.absmax[1] =
        entities[i].v.absmax[2] = 64;
  }
  for (i = 0; i < count; i++) {
    link_t *head = &nodes[i].solid_edicts, *entry = &entities[i + 1].area;
    head->prev = head;
    head->next = head;
    if ((i + seed) % 5) {
      head->prev = entry;
      head->next = entry;
      entry->prev = head;
      entry->next = head;
    }
    if (!shape) {
      nodes[i].axis = i < 15 ? (int)(i % 3) : -1;
      if (i < 15) {
        nodes[i].children[0] = nodes + 2 * i + 1;
        nodes[i].children[1] = nodes + 2 * i + 2;
      }
    } else {
      nodes[i].axis = i < 64 ? (int)(i % 3) : -1;
      if (i < 64) {
        nodes[i].children[shape == 1 ? 0 : 1] = nodes + 64;
        nodes[i].children[shape == 1 ? 1 : 0] = nodes + i + 1;
      }
    }
    nodes[i].dist = ((int)((i + seed) % 5) - 2) * .5f;
    entities[i + 1].v.flags = (i + seed) % 4 ? 0 : FL_MONSTER;
    if (seed % 7 == 0 && i % 3 == 0)
      entities[i + 1].v.solid = SOLID_NOT;
    if (seed % 13 == 0 && i % 7 == 0)
      entities[i + 1].v.solid = SOLID_TRIGGER;
    if (seed % 5 == 0 && i % 3 == 1)
      entities[i + 1].v.solid = SOLID_BSP;
    if (seed % 11 == 0 && i % 3 == 2)
      entities[i + 1].v.size[0] = 0;
    if (seed % 9 == 0 && i % 3 == 0)
      entities[i + 1].v.owner = sizeof(edict_t);
    if (seed % 17 == 0 && i % 5 == 0)
      entities[i + 1].v.absmin[1] = 100;
  }
  for (i = 0; i < 3; i++) {
    begin[i] = (int)i - 16;
    finish[i] = 16 - i;
    mins[i] = -2;
    maxs[i] = 2;
    initial.boxmins[i] = seed % 4 == 0 ? -64 : ((int)(seed % 5) - 2);
    initial.boxmaxs[i] = seed % 4 == 0 ? 64 : initial.boxmins[i] + (seed % 3);
    initial.mins2[i] = -15;
    initial.maxs2[i] = 15;
  }
  if (seed % 19 == 0) {
    unsigned bits = 0x7fc01234;
    memcpy(&initial.boxmins[seed % 3], &bits, 4);
  }
  if (seed % 23 == 0) {
    unsigned bits = 0x7fc01234;
    memcpy(&nodes[0].dist, &bits, 4);
  }
  initial.start = begin;
  initial.end = finish;
  initial.mins = mins;
  initial.maxs = maxs;
  initial.type = seed % 3;
  initial.passedict = seed % 3 ? entities + 1 : NULL;
  entities[1].v.owner = seed % 2 ? 0 : 3 * sizeof(edict_t);
  initial.trace.fraction = 1;
  initial.trace.allsolid = seed % 29 == 0;
  initial.trace.startsolid = seed % 7 == 0;
}
typedef struct {
  moveclip_t clip;
  helper_log_t log[256];
  unsigned calls, nodes, abi, errors, error_kind;
  unsigned short cw, top, tag;
  double preloaded[2];
  char message[128];
} snapshot_t;
static snapshot_t control, candidate;
static void capture(snapshot_t *out, void (*fn)(areanode_t *, moveclip_t *),
                    unsigned short cw, unsigned preloaded) {
  unsigned short status, env[14];
  memset(out, 0, sizeof(*out));
  memset(log_entries, 0, sizeof(log_entries));
  memcpy(&clip, &initial, sizeof(clip));
  helper_count = bench486_cliptolinks_asm_calls = errors = error_kind = 0;
  memset(error_message, 0, sizeof(error_message));
  __asm__ __volatile__("fninit; fldcw %0" ::"m"(cw) : "memory");
  if (preloaded)
    __asm__ __volatile__("fld1; fldz" ::: "memory");
  if (!setjmp(error_jump))
    out->abi = CallClipWithAbi(fn, nodes, &clip);
  if (preloaded)
    __asm__ __volatile__("fstpl %0; fstpl %1"
                         : "=m"(out->preloaded[0]),
                           "=m"(out->preloaded[1])::"memory");
  __asm__ __volatile__("fnstcw %0; fnstsw %1"
                       : "=m"(out->cw), "=m"(status)::"memory");
  __asm__ __volatile__("fnstenv %0; fldenv %0" : "=m"(env)::"memory");
  out->top = status & 0x3800;
  out->tag = env[4];
  memcpy(&out->clip, &clip, sizeof(clip));
  memcpy(out->log, log_entries, sizeof(log_entries));
  out->calls = helper_count;
  out->nodes = bench486_cliptolinks_asm_calls;
  out->errors = errors;
  out->error_kind = error_kind;
  memcpy(out->message, error_message, sizeof(error_message));
}
int main(void) {
  static const unsigned precision[] = {0, 0x200, 0x300};
  unsigned p, r, shape, seed, preloaded, i, ok = 1;
  unsigned short cw, original;
  FILE *report;
  __asm__ __volatile__("fnstcw %0" : "=m"(original));
  for (p = 0; p < 3 && ok; p++)
    for (r = 0; r < 4 && ok; r++) {
      cw = (original & ~0xf00) | precision[p] | (r << 10);
      for (shape = 0; shape < 3 && ok; shape++)
        for (seed = 0; seed < 96 && ok; seed++)
          for (preloaded = 0; preloaded < 2 && ok; preloaded++) {
            seed_value = seed;
            setup(seed, shape);
            capture(&control, SV_ClipToLinksControl, cw, preloaded);
            capture(&candidate, SV_ClipToLinksCandidate, cw, preloaded);
            checks++;
            if (memcmp(&control, &candidate, sizeof(control)) ||
                control.errors || control.abi || control.cw != cw ||
                control.top || control.tag != 0xffff || !control.nodes ||
                (preloaded && !control.error_kind &&
                 (control.preloaded[0] != 0.0 ||
                  control.preloaded[1] != 1.0))) {
              for (i = 0; i < sizeof(control); i++)
                if (((byte *)&control)[i] != ((byte *)&candidate)[i])
                  break;
              printf("FAIL shape=%u seed=%u preload=%u cw=%x byte=%u "
                     "nodes=%u/%u calls=%u/%u error=%u abi=%u\n",
                     shape, seed, preloaded, cw, i, control.nodes,
                     candidate.nodes, control.calls, candidate.calls,
                     control.error_kind, control.abi);
              ok = 0;
            }
          }
    }
  __asm__ __volatile__("fninit; fldcw %0" ::"m"(original) : "memory");
  report = fopen("RESULT.TXT", "w");
  if (!report)
    return 2;
  fprintf(report,
          "%s %u clip-links cases; balanced and deep left/right trees; exact "
          "clip, helper order/bounds, errors, counters, ABI and x87 "
          "modes/preloaded values\n",
          ok ? "PASS" : "FAIL", checks);
  fclose(report);
  return ok ? 0 : 1;
}
