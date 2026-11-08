#include "quakedef.h"
#include <setjmp.h>
#include <stddef.h>
#include <stdarg.h>
#include <string.h>

static dprograms_t program;
static dfunction_t functions[16];
static dstatement_t statements[16];
static float storage[544];
static char strings[256] = "\0alpha\0beta\0fixture\0";
static edict_t entities[3];
dprograms_t *progs = &program;
dfunction_t *pr_functions = functions;
dstatement_t *pr_statements = statements;
float *pr_globals = storage + 16;
globalvars_t *pr_global_struct = (globalvars_t *)(storage + 16);
char *pr_strings = strings;
server_t sv;
static void builtin(void);
static builtin_t builtins[2] = {NULL, builtin};
builtin_t *pr_builtins = builtins;
int pr_numbuiltins = 2;
extern int pr_depth, pr_xstatement, localstack_used;
void PR_ExecuteProgramControl(func_t f);
void PR_ExecuteProgramCandidate(func_t f);
static void (*selected)(func_t);
static jmp_buf error_jump;
static int failure_kind, printed, builtin_kind;
static char error_text[128];

void Con_Printf(char *fmt, ...) {
    (void)fmt;
    printed++;
}
void ED_Print(edict_t *ed) {
    (void)ed;
    printed++;
}
char *PR_GlobalString(int ofs) {
    (void)ofs;
    return "global";
}
char *PR_GlobalStringNoContents(int ofs) {
    (void)ofs;
    return "global";
}
void Host_Error(char *fmt, ...) {
    failure_kind = 1;
    strncpy(error_text, fmt, sizeof(error_text) - 1);
    longjmp(error_jump, 1);
}
void Sys_Error(char *fmt, ...) {
    failure_kind = 2;
    strncpy(error_text, fmt, sizeof(error_text) - 1);
    longjmp(error_jump, 1);
}
static void builtin(void) {
    pr_globals[100] += 1.0f;
    if (builtin_kind == 1)
        pr_trace = true;
    if (builtin_kind == 2)
        selected(3);
}
static unsigned short tag(void) {
    unsigned short env[14];
    __asm__ __volatile__("fnstenv %0; fldenv %0" : "=m"(env)::"memory");
    return env[4];
}
static void statement(int index, int op, int a, int b, int c) {
    statements[index].op = op;
    statements[index].a = a;
    statements[index].b = b;
    statements[index].c = c;
}
static void setup(int op, int variation) {
    int i;
    eval_t *a, *b;
    static const unsigned patterns[] = {0,          0x80000000, 0x3fa00000, 0xc0200000,
                                        0x7fc01234, 0x7f800000, 1,          0x80000001};
    memset(&program, 0, sizeof(program));
    memset(functions, 0, sizeof(functions));
    memset(statements, 0, sizeof(statements));
    memset(storage, 0, sizeof(storage));
    memset(entities, 0, sizeof(entities));
    memset(&sv, 0, sizeof(sv));
    memset(error_text, 0, sizeof(error_text));
    for (i = 0; i < 512; i++)
        pr_globals[i] = (i - 200) * .125f;
    for (i = 0; i < (int)(sizeof(entvars_t) / 4); i++)
        ((float *)&entities[1].v)[i] = (i - 100) * .25f;
    program.numfunctions = 16;
    program.numstatements = 16;
    program.numglobals = 512;
    sv.edicts = entities;
    sv.num_edicts = 3;
    sv.state = ss_active;
    functions[1].first_statement = 1;
    functions[1].parm_start = 300;
    functions[1].locals = 6;
    functions[2].first_statement = -1;
    functions[3].first_statement = 3;
    functions[3].parm_start = 320;
    functions[3].locals = 6;
    pr_global_struct->self = sizeof(edict_t);
    pr_global_struct->time = 1.5f;
    pr_depth = localstack_used = pr_xstatement = pr_argc = 0;
    pr_xfunction = NULL;
    pr_trace = false;
    failure_kind = printed = builtin_kind = 0;
    a = (eval_t *)&pr_globals[64];
    b = (eval_t *)&pr_globals[68];
    memcpy(a, &patterns[variation % 8], 4);
    memcpy(b, &patterns[(variation + 3) % 8], 4);
    statement(1, op, 64, 68, 72);
    statement(2, OP_RETURN, 80, 0, 0);
    statement(3, OP_ADD_F, 64, 68, 104);
    statement(4, OP_RETURN, 104, 0, 0);
    if (variation == 8 || variation == 9) {
        statement(1, op, 64, 65, variation == 8 ? 66 : 64);
        b = (eval_t *)&pr_globals[65];
    }
    if (op == OP_EQ_S || op == OP_NE_S || op == OP_NOT_S) {
        a->string = variation % 2 ? 1 : 0;
        b->string = variation % 3 ? 7 : 1;
    }
    if (op == OP_EQ_E || op == OP_NE_E || op == OP_NOT_ENT) {
        a->edict = variation % 2 ? sizeof(edict_t) : 0;
        b->edict = sizeof(edict_t);
    }
    if (op == OP_EQ_FNC || op == OP_NE_FNC || op == OP_NOT_FNC) {
        a->function = variation % 2 ? 2 : 0;
        b->function = 2;
    }
    if (op >= OP_LOAD_F && op <= OP_ADDRESS) {
        a->edict = sizeof(edict_t);
        b->_int = offsetof(entvars_t, origin) / 4 + variation % 3;
    }
    if (op >= OP_STOREP_F && op <= OP_STOREP_FNC) {
        b->_int = sizeof(edict_t) + offsetof(edict_t, v) + offsetof(entvars_t, origin) +
                  4 * (variation % 3);
    }
    if (op == OP_IF || op == OP_IFNOT) {
        a->_int = variation % 2;
        statement(1, op, 64, 2, -200);
        statement(2, OP_ADD_F, 64, 68, 104);
        statement(3, OP_RETURN, 80, 0, 0);
    }
    if (op == OP_GOTO) {
        statement(1, op, 2, -200, 30000);
        statement(3, OP_RETURN, 80, 0, 0);
    }
    if (op >= OP_CALL0 && op <= OP_CALL8) {
        a->function = 2;
        builtin_kind = variation % 3;
        if (variation >= 6) {
            builtin_kind = 0;
            functions[2].first_statement = 3;
            functions[2].parm_start = 200;
            functions[2].locals = 24;
            functions[2].numparms = 8;
            for (i = 0; i < 8; i++)
                functions[2].parm_size[i] = 3;
        }
    }
    if (op == OP_STATE) {
        a->_float = variation * .25f;
        b->function = 3;
    }
}
typedef struct {
    float globals[544];
    edict_t edicts[3];
    dfunction_t funcs[16];
    int failed, prints, depth, locals, argc, xstatement, trace, function_index;
    unsigned short cw, top, tagword;
    char error[128];
} result_t;
static result_t control, candidate;
static int checks;
static unsigned random_word(unsigned *state) {
    *state = *state * 1664525u + 1013904223u;
    return *state;
}
static void mixed_program(int seed) {
    static const int ops[] = {OP_ADD_F, OP_SUB_F,  OP_MUL_F,  OP_DIV_F, OP_ADD_V, OP_SUB_V,
                              OP_MUL_V, OP_MUL_FV, OP_MUL_VF, OP_EQ_F,  OP_LT,    OP_NOT_F};
    unsigned random = 0x9e3779b9u ^ (unsigned)seed * 0x85ebca6bu, word;
    int i, a, b, c, op;
    for (i = 64; i < 132; i++) {
        word = random_word(&random);
        word = (word & 0x807fffffu) | ((116u + ((word >> 24) & 15u)) << 23);
        memcpy(&pr_globals[i], &word, 4);
    }
    for (i = 1; i <= 8; i++) {
        op = ops[(random_word(&random) >> 16) % 12];
        a = 66 + ((random_word(&random) >> 16) % 58);
        b = 66 + ((random_word(&random) >> 16) % 58);
        c = seed % 3 == 0   ? a + 1
            : seed % 3 == 1 ? b - 1
                            : 66 + ((random_word(&random) >> 16) % 58);
        statement(i, op, a, b, c);
    }
    statement(9, OP_RETURN, 96, 0, 0);
}
static void capture(void (*fn)(func_t), result_t *out, int op, int variation, int special,
                    unsigned short cw) {
    int function = 1;
    setup(op, variation);
    selected = fn;
    if (special == 1) {
        statement(1, OP_SUB_F, 120, 121, 120);
        statement(2, OP_IF, 120, -1, 30000);
        statement(3, OP_RETURN, 80, 0, 0);
        pr_globals[120] = 3;
        pr_globals[121] = 1;
    }
    if (special == 2)
        statement(1, OP_GOTO, 0, -200, 30000);
    if (special == 3)
        ((eval_t *)&pr_globals[64])->function = 0;
    if (special == 4)
        functions[2].first_statement = -99;
    if (special == 5) {
        statement(1, OP_ADDRESS, 64, 68, 72);
        ((eval_t *)&pr_globals[64])->edict = 0;
        ((eval_t *)&pr_globals[68])->_int = 0;
    }
    if (special == 6)
        function = 0;
    if (special == 7)
        function = 16;
    if (special == 8)
        mixed_program(variation);
    memset(out, 0, sizeof(*out));
    __asm__ __volatile__("fnclex; fldcw %0" ::"m"(cw) : "memory");
    if (!setjmp(error_jump))
        fn(function);
    __asm__ __volatile__("fnstcw %0; fnstsw %1" : "=m"(out->cw), "=m"(out->top)::"memory");
    out->top &= 0x3800;
    out->tagword = tag();
    memcpy(out->globals, storage, sizeof(storage));
    memcpy(out->edicts, entities, sizeof(entities));
    memcpy(out->funcs, functions, sizeof(functions));
    out->failed = failure_kind;
    out->prints = printed;
    out->depth = pr_depth;
    out->locals = localstack_used;
    out->argc = pr_argc;
    out->xstatement = pr_xstatement;
    out->trace = pr_trace;
    out->function_index = pr_xfunction ? (int)(pr_xfunction - functions) : -1;
    memcpy(out->error, error_text, sizeof(error_text));
}
static int compare(int op, int variation, int special, unsigned short cw) {
    int i;
    capture(PR_ExecuteProgramControl, &control, op, variation, special, cw);
    capture(PR_ExecuteProgramCandidate, &candidate, op, variation, special, cw);
    checks++;
    for (i = 0; i < (int)sizeof(control); i++)
        if (((byte *)&control)[i] != ((byte *)&candidate)[i]) {
            printf("FAIL op=%d variation=%d special=%d cw=%x byte=%d control=%u candidate=%u\n", op,
                   variation, special, cw, i, ((byte *)&control)[i], ((byte *)&candidate)[i]);
            return 0;
        }
    if (!control.failed && (control.cw != cw || control.top || control.tagword != 0xffff)) {
        printf("FAIL FPU op=%d cw=%x/%x top=%x tag=%x\n", op, control.cw, cw, control.top,
               control.tagword);
        return 0;
    }
    return 1;
}
int main(void) {
    unsigned short original, cw;
    static const int precision[] = {0, 0x200, 0x300};
    int p, r, op, v, s, ok = 1;
    FILE *report;
    __asm__ __volatile__("fnstcw %0" : "=m"(original));
    for (p = 0; p < 3 && ok; p++)
        for (r = 0; r < 4 && ok; r++) {
            cw = (original & ~0xf00) | precision[p] | (r << 10);
            for (op = 0; op <= OP_BITOR && ok; op++)
                for (v = 0; v < 10 && ok; v++)
                    ok = compare(op, v, 0, cw);
            for (s = 1; s <= 7 && ok; s++)
                ok = compare(OP_CALL0, 0, s, cw);
            for (v = 0; v < 256 && ok; v++)
                ok = compare(OP_ADD_F, v, 8, cw);
        }
    __asm__ __volatile__("fnclex; fldcw %0" ::"m"(original));
    report = fopen("RESULT.TXT", "w");
    if (!report)
        return 2;
    fprintf(report,
            "%s %d interpreter cases; all 66 opcodes, 10 input/alias variants, 12 x87 modes, 256 "
            "mixed/overlapping arithmetic sequences per mode, branches/calls/trace/errors; exact "
            "globals/edicts/profiles and FPU\n",
            ok ? "PASS" : "FAIL", checks);
    fclose(report);
    return ok ? 0 : 1;
}
