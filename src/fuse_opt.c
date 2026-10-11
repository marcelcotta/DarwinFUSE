/*
 * DarwinFUSE — standard FUSE option parsing implementation
 *
 * Compatible with libfuse 2.x fuse_opt_parse() and friends.
 *
 * Copyright (c) 2026 Marcel Cotta. All rights reserved.
 * Licensed under the MIT License.
 */

#include <fuse_opt.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

/* ---- Argument list management ---- */

int fuse_opt_add_arg(struct fuse_args *args, const char *arg)
{
    if (!args || !arg) return -1;

    char **new_argv = realloc(args->allocated ? args->argv : NULL,
                               (size_t)(args->argc + 2) * sizeof(char *));
    if (!new_argv) {
        /* If first alloc, need to copy existing argv */
        if (!args->allocated) {
            new_argv = malloc((size_t)(args->argc + 2) * sizeof(char *));
            if (!new_argv) return -1;
            for (int i = 0; i < args->argc; i++)
                new_argv[i] = strdup(args->argv[i]);
        } else {
            return -1;
        }
    } else if (!args->allocated) {
        /* realloc on non-allocated argv: need to copy existing strings */
        char **copy = malloc((size_t)(args->argc + 2) * sizeof(char *));
        if (!copy) { free(new_argv); return -1; }
        for (int i = 0; i < args->argc; i++)
            copy[i] = strdup(args->argv[i]);
        new_argv = copy;
    }

    new_argv[args->argc] = strdup(arg);
    if (!new_argv[args->argc]) return -1;
    args->argc++;
    new_argv[args->argc] = NULL;
    args->argv = new_argv;
    args->allocated = 1;
    return 0;
}

int fuse_opt_insert_arg(struct fuse_args *args, int pos, const char *arg)
{
    if (!args || !arg || pos < 0 || pos > args->argc)
        return -1;

    /* Add arg at end first */
    if (fuse_opt_add_arg(args, arg) < 0)
        return -1;

    /* Shift elements from pos to argc-2 right by 1 */
    char *new_arg = args->argv[args->argc - 1];
    for (int i = args->argc - 1; i > pos; i--)
        args->argv[i] = args->argv[i - 1];
    args->argv[pos] = new_arg;

    return 0;
}

void fuse_opt_free_args(struct fuse_args *args)
{
    if (!args) return;
    if (args->allocated && args->argv) {
        for (int i = 0; i < args->argc; i++)
            free(args->argv[i]);
        free(args->argv);
    }
    args->argv = NULL;
    args->argc = 0;
    args->allocated = 0;
}

int fuse_opt_add_opt(char **opts, const char *opt)
{
    if (!opts || !opt) return -1;

    if (*opts) {
        size_t old_len = strlen(*opts);
        size_t new_len = old_len + 1 + strlen(opt) + 1;
        char *new_str = realloc(*opts, new_len);
        if (!new_str) return -1;
        new_str[old_len] = ',';
        strcpy(new_str + old_len + 1, opt);
        *opts = new_str;
    } else {
        *opts = strdup(opt);
        if (!*opts) return -1;
    }
    return 0;
}

/* Like fuse_opt_add_opt, but a ',' or '\' inside the option is escaped with '\'. */
int fuse_opt_add_opt_escaped(char **opts, const char *opt)
{
    if (!opts || !opt) return -1;

    size_t extra = 0;
    for (const char *p = opt; *p; p++)
        if (*p == ',' || *p == '\\') extra++;

    char *escaped = malloc(strlen(opt) + extra + 1);
    if (!escaped) return -1;
    char *q = escaped;
    for (const char *p = opt; *p; p++) {
        if (*p == ',' || *p == '\\') *q++ = '\\';
        *q++ = *p;
    }
    *q = '\0';

    int rc = fuse_opt_add_opt(opts, escaped);
    free(escaped);
    return rc;
}

/* ---- Pattern matching ---- */

/*
 * Match a single option template against an argument.
 * Templates can be:
 *   "foo"        — exact match (boolean option)
 *   "foo="       — prefix match with value (foo=bar)
 *   "foo=%s"     — prefix match, value is a string
 *   "foo=%d"     — prefix match, value is an int
 *   "foo=%u"     — prefix match, value is unsigned
 *   "-x "        — single char flag with space-separated value
 *   "-x %s"      — single char flag with value
 */
static int match_template(const char *templ, const char *arg,
                           const char **val_out)
{
    if (!templ || !arg) return 0;

    /* Find if template has a value specifier */
    const char *perc = strchr(templ, '%');
    const char *eq   = strchr(templ, '=');

    if (perc) {
        /* Template has a format specifier like "foo=%s" or "-x %s" */
        size_t prefix_len;
        if (eq && eq < perc) {
            /* "foo=%s" style — match prefix including = */
            prefix_len = (size_t)(eq - templ) + 1;
        } else {
            /* "-x %s" style — match up to space before % */
            const char *space = strchr(templ, ' ');
            if (space && space < perc)
                prefix_len = (size_t)(space - templ);
            else
                prefix_len = (size_t)(perc - templ);
        }

        if (strncmp(templ, arg, prefix_len) == 0) {
            if (val_out) *val_out = arg + prefix_len;
            return 1;
        }
        return 0;
    }

    if (eq) {
        /* "foo=" style — prefix match */
        size_t prefix_len = (size_t)(eq - templ) + 1;
        if (strncmp(templ, arg, prefix_len) == 0) {
            if (val_out) *val_out = arg + prefix_len;
            return 1;
        }
        return 0;
    }

    /* "-x " style: the option letter(s), then a value, attached or as the next
     * argument. The value is whatever follows the template without its space. */
    size_t tlen = strlen(templ);
    if (tlen > 1 && templ[tlen - 1] == ' ') {
        size_t prefix_len = tlen - 1;
        if (strncmp(templ, arg, prefix_len) == 0) {
            if (val_out) *val_out = arg + prefix_len;
            return 1;
        }
        return 0;
    }

    /* Exact match */
    if (strcmp(templ, arg) == 0) {
        if (val_out) *val_out = NULL;
        return 1;
    }

    return 0;
}

int fuse_opt_match(const struct fuse_opt opts[], const char *opt)
{
    if (!opts || !opt) return 0;
    for (int i = 0; opts[i].templ; i++) {
        if (match_template(opts[i].templ, opt, NULL))
            return 1;
    }
    return 0;
}

/* ---- Main parser ---- */

/*
 * An entry whose offset is -1U is a key entry. Earlier DarwinFUSE headers used
 * the full-width value, which is accepted as well.
 */
static int is_key_entry(const struct fuse_opt *opt)
{
    return opt->offset == (unsigned long)(unsigned int)-1 ||
           opt->offset == (unsigned long)-1;
}

/*
 * Decide what happens to an argument for a given key, as libfuse does: DISCARD
 * and KEEP are settled without calling the function. Returns -1 on error, 0 to
 * drop the argument, 1 to keep it.
 */
static int call_proc(fuse_opt_proc_t proc, void *data, const char *arg,
                     int key, struct fuse_args *outargs)
{
    if (key == FUSE_OPT_KEY_DISCARD) return 0;
    if (key == FUSE_OPT_KEY_KEEP) return 1;
    if (!proc) return 1;

    int rc = proc(data, arg, key, outargs);
    if (rc < 0) return -1;
    return rc ? 1 : 0;
}

/*
 * Apply a matched option: set the value at the specified offset
 * in the data structure, or return the key for callback processing.
 */
static int apply_opt(const struct fuse_opt *opt, void *data,
                     const char *val, const char *arg,
                     fuse_opt_proc_t proc, struct fuse_args *outargs)
{
    if (!opt) {
        /* No matching template found — pass to callback as KEY_OPT */
        return call_proc(proc, data, arg, FUSE_OPT_KEY_OPT, outargs);
    }

    if (is_key_entry(opt))
        return call_proc(proc, data, arg, opt->value, outargs);

    /* Set value at offset */
    if (data) {
        void *dst = (char *)data + opt->offset;
        const char *perc = strchr(opt->templ, '%');
        if (perc) {
            char fmt = perc[1];
            switch (fmt) {
            case 's': {
                /* The program keeps this pointer after the arguments are gone, so
                 * give it its own copy (libfuse does; the caller may free it). */
                char *copy = strdup(val ? val : arg);
                if (!copy) return -1;
                *(char **)dst = copy;
                break;
            }
            case 'd':
                *(int *)dst = val ? atoi(val) : opt->value;
                break;
            case 'u':
                *(unsigned *)dst = val ? (unsigned)strtoul(val, NULL, 10) : (unsigned)opt->value;
                break;
            case 'l':
                if (perc[2] == 'u')
                    *(unsigned long *)dst = val ? strtoul(val, NULL, 10) : (unsigned long)opt->value;
                else
                    *(long *)dst = val ? strtol(val, NULL, 10) : (long)opt->value;
                break;
            default:
                *(int *)dst = opt->value;
                break;
            }
        } else {
            /* Boolean-style: set to opt->value */
            *(int *)dst = opt->value;
        }
    }

    return 0;  /* consumed */
}

static const struct fuse_opt *find_opt(const struct fuse_opt opts[],
                                       const char *arg, const char **val)
{
    if (!opts) return NULL;
    for (int j = 0; opts[j].templ; j++)
        if (match_template(opts[j].templ, arg, val))
            return &opts[j];
    return NULL;
}

/*
 * Split "a,b\,c" at unescaped commas; "\x" stands for x. Calls fn for each
 * option and stops at the first failure. Returns -1 on error.
 */
static int for_each_suboption(const char *list,
                              int (*fn)(const char *tok, void *ctx), void *ctx)
{
    char *tok = malloc(strlen(list) + 1);
    if (!tok) return -1;

    int rc = 0;
    const char *p = list;
    while (rc == 0) {
        size_t n = 0;
        while (*p && *p != ',') {
            if (*p == '\\' && p[1]) p++;
            tok[n++] = *p++;
        }
        tok[n] = '\0';
        if (n > 0)
            rc = fn(tok, ctx);
        if (!*p) break;
        p++;                       /* skip the comma */
    }

    free(tok);
    return rc;
}

struct parse_ctx {
    void                  *data;
    const struct fuse_opt *opts;
    fuse_opt_proc_t        proc;
    struct fuse_args      *outargs;
};

static int handle_suboption(const char *tok, void *vctx)
{
    struct parse_ctx *c = vctx;
    const char *val = NULL;
    const struct fuse_opt *matched = find_opt(c->opts, tok, &val);

    int rc = apply_opt(matched, c->data, val, tok, c->proc, c->outargs);
    if (rc < 0) return -1;
    if (rc == 1) {
        /* Keep: pass it on as -o <option> */
        if (fuse_opt_add_arg(c->outargs, "-o") < 0 ||
            fuse_opt_add_arg(c->outargs, tok) < 0)
            return -1;
    }
    return 0;
}

int fuse_opt_parse(struct fuse_args *args, void *data,
                   const struct fuse_opt opts[],
                   fuse_opt_proc_t proc)
{
    if (!args || !args->argv)
        return 0;

    struct fuse_args outargs = FUSE_ARGS_INIT(0, NULL);
    struct parse_ctx ctx = { data, opts, proc, &outargs };

    /* Always keep argv[0] (program name) */
    if (args->argc > 0)
        fuse_opt_add_arg(&outargs, args->argv[0]);

    for (int i = 1; i < args->argc; i++) {
        const char *arg = args->argv[i];
        int keep = 0;

        /* "-o a,b" and "-oa,b" both carry a comma-separated option list */
        const char *optlist = NULL;
        if (strcmp(arg, "-o") == 0 && i + 1 < args->argc)
            optlist = args->argv[++i];
        else if (strncmp(arg, "-o", 2) == 0 && arg[2] != '\0')
            optlist = arg + 2;

        if (optlist) {
            if (for_each_suboption(optlist, handle_suboption, &ctx) < 0) {
                fuse_opt_free_args(&outargs);
                return -1;
            }
            continue;
        }

        if (arg[0] == '-') {
            /* Flag argument */
            const char *val = NULL;
            const struct fuse_opt *matched = find_opt(opts, arg, &val);
            char *joined = NULL;

            /* "-p " takes its value as the next argument; the function sees the
             * two joined ("-p2222"), as with libfuse. */
            if (matched) {
                size_t tlen = strlen(matched->templ);
                if (tlen > 1 && matched->templ[tlen - 1] == ' ' &&
                    strchr(matched->templ, '%') == NULL &&
                    strlen(arg) == tlen - 1 && i + 1 < args->argc) {
                    const char *next = args->argv[++i];
                    joined = malloc(strlen(arg) + strlen(next) + 1);
                    if (!joined) { fuse_opt_free_args(&outargs); return -1; }
                    strcpy(joined, arg);
                    strcat(joined, next);
                    arg = joined;
                    val = next;
                } else if (strchr(matched->templ, '%') && strchr(matched->templ, ' ') &&
                           i + 1 < args->argc) {
                    val = args->argv[++i];
                }
            }

            int rc = apply_opt(matched, data, val, arg, proc, &outargs);
            if (rc < 0) {
                free(joined);
                fuse_opt_free_args(&outargs);
                return -1;
            }
            if (rc == 1) {
                if (fuse_opt_add_arg(&outargs, arg) < 0) {
                    free(joined);
                    fuse_opt_free_args(&outargs);
                    return -1;
                }
            }
            free(joined);
            continue;
        }

        /* Non-option argument */
        int rc = call_proc(proc, data, arg, FUSE_OPT_KEY_NONOPT, &outargs);
        if (rc < 0) {
            fuse_opt_free_args(&outargs);
            return -1;
        }
        if (rc == 1) keep = 1;

        if (keep)
            fuse_opt_add_arg(&outargs, arg);
    }

    /* Replace original args with filtered output */
    if (args->allocated) {
        for (int i = 0; i < args->argc; i++)
            free(args->argv[i]);
        free(args->argv);
    }
    *args = outargs;

    return 0;
}
