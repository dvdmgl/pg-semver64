//  -*- tab-width:4; c-basic-offset:4; indent-tabs-mode:nil;  -*-
/*
 * PostgreSQL type definitions for semver type
 * Written by:
 * + Sam Vilain <sam@vilain.net>
 * + Tom Davis <tom@recursivedream.com>
 * + Xavier Caron <xcaron@gmail.com>
 *
 * Copyright 2010-2020 The pg-semver Maintainers. This program is Free
 * Software; see the LICENSE file for the license conditions.
 *
 * PostgreSQL type definitions for semver64 type
 * Written by:
 * + David Miguel <https://github.com/dvdmgl>
 *
 * Copyright 2010-2020 The pg-semver Maintainers. This program is Free
 * Software; see the LICENSE file for the license conditions.
 */

#include "postgres.h"
#include <string.h>
#include <ctype.h>
#include <limits.h>
#include <pcre.h>
#include <stdint.h>
#include <inttypes.h>
#include "libpq/pqformat.h"
#include "utils/builtins.h"

#ifdef PG_MODULE_MAGIC
PG_MODULE_MAGIC;
#endif

const char *SEMVER_PART[3] = {"MAJOR", "MINOR", "PATCH"};
/* IO methods */
Datum       semver64_in(PG_FUNCTION_ARGS);
Datum       semver64_out(PG_FUNCTION_ARGS);

Datum       semver64_eq(PG_FUNCTION_ARGS);
Datum       hash_semver64(PG_FUNCTION_ARGS);
Datum       semver64_ne(PG_FUNCTION_ARGS);
Datum       semver64_lt(PG_FUNCTION_ARGS);
Datum       semver64_le(PG_FUNCTION_ARGS);
Datum       semver64_ge(PG_FUNCTION_ARGS);
Datum       semver64_gt(PG_FUNCTION_ARGS);
Datum       semver64_cmp(PG_FUNCTION_ARGS);

/* these typecasts are necessary for passing to functions that take text */
Datum       text_to_semver64(PG_FUNCTION_ARGS);
Datum       semver64_to_text(PG_FUNCTION_ARGS);

/* this constructor gives access to the lax parsing mode */
Datum       to_semver64(PG_FUNCTION_ARGS);

Datum       is_semver64(PG_FUNCTION_ARGS);

Datum       semver64_smaller(PG_FUNCTION_ARGS);
Datum       semver64_larger(PG_FUNCTION_ARGS);

/* these functions allow users to access individual parts of the semver64 */
Datum       get_semver64_major(PG_FUNCTION_ARGS);
Datum       get_semver64_minor(PG_FUNCTION_ARGS);
Datum       get_semver64_patch(PG_FUNCTION_ARGS);
Datum       get_semver64_prerelease(PG_FUNCTION_ARGS);

void _PG_init(void);


/* memory/heap structure (not for binary marshalling) */
typedef struct semver64
{
    int32 vl_len_;  /* varlena header */
    uint64_t numbers[3];
    char prerel[]; /* pre-release, including the null byte for convenience, does not include the pre-release char '-' */
} semver64;

static void *
pgpcre_malloc(size_t size)
{
    return palloc(size);
}


static void
pgpcre_free(void *ptr)
{
    pfree(ptr);
}


void
_PG_init(void)
{
    pcre_malloc = pgpcre_malloc;
    pcre_free = pgpcre_free;
}

#define PG_GETARG_SEMVER64_P(n) (semver64*)PG_GETARG_POINTER(n)

// forward declarations, mostly to shut the compiler up but some are
// actually necessary.
char*   emit_semver64(semver64* version);
semver64* make_semver64(const uint64_t *numbers, const char* prerel);
semver64* parse_semver64(char* str, bool throw, bool *bad);
int     prerelcmp(const char* a, const char* b);
int     _semver64_cmp(semver64* a, semver64* b);
char*   strip_meta(const char* str);
int     tail_cmp(char *lhs, char *rhs);

semver64* make_semver64(const uint64_t *numbers, const char* prerel) {
    int varsize = offsetof(semver64, prerel) + (prerel ? strlen(prerel) : 0) + 1;
    semver64 *rv = palloc(varsize);
    int i;
    SET_VARSIZE(rv, varsize);
    for (i = 0; i < 3; i++) {
        rv->numbers[i] = numbers[i];
    }
    if (prerel) {
        strcpy(rv->prerel, prerel);
    }
    else {
        rv->prerel[0] = '\0';
    }
    return rv;
}

#define OVECCOUNT 18    /* should be a multiple of 3 */

semver64* parse_semver64(char* str, bool throw, bool* bad)
{
  const char *error;
  int len, i, erroffset, rc;
  semver64* newval;
  char* patch = 0;
  uint64_t parts[] = {0, 0, 0};
  char *regexString = "^[ ]*(0|[1-9][0-9]*)[.](0|[1-9][0-9]*)[.](0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*)(?:[.](?:0|[1-9][0-9]*|[0-9]*[a-zA-Z-][0-9a-zA-Z-]*))*))?(?:[+]([0-9a-zA-Z-]+(?:[.][0-9a-zA-Z-]+)*))?$";
  int ovector[OVECCOUNT];
  pcre *re;
  len = strlen(str);
  *bad = false;
  re = pcre_compile(
    regexString,          /* the pattern */
    0,                    /* default options */
    &error,               /* for error message */
    &erroffset,           /* for error offset */
    NULL);                /* use default character tables */

  rc = pcre_exec(
    re,                   /* the compiled pattern */
    NULL,                 /* no extra data - we didn't study the pattern */
    str,                  /* the subject string */
    len,                  /* the length of the subject */
    0,                    /* start at offset 0 in the subject */
    0,                    /* default options */
    ovector,              /* output vector for substring information */
    OVECCOUNT);           /* number of elements in the output vector */

  if (rc < 0) {
    *bad = true;
    if (throw) {
        elog(ERROR, "invalid semver64 value '%s'", str);
    }
  } else {
      for (i = 1; i < rc && i < 4; i++)
      {
        char *substring_start = str + ovector[2*i];
        int substring_length = ovector[2*i+1] - ovector[2*i];
        int n = 0;
        int num = 0;
        if (substring_length > 20) {
            *bad = true;
            if (throw) {
                elog(ERROR, "bad semver value '%s': version %s exceeds 64-bit range", str, SEMVER_PART[i-1]);
            }
            break;
        }
        if (substring_length == 20) {
          char str_number[21];
          memcpy(str_number, str + ovector[2*i], 20);
          str_number[substring_length] = '\0';
          if (strcmp(str_number, "18446744073709551615") > 0) {
            *bad = true;
            if (throw){
                elog(ERROR, "bad semver value '%s': version %s exceeds 64-bit range", str, SEMVER_PART[i-1]);
            }
            break;
          }
        }
        while(n++ < substring_length) {
          num = (num << 1) + (num << 3) + *substring_start++ - '0';
        }
        parts[i-1] = num;
      }

      if (rc >= 4) {
        int start = ovector[8] > -1 ? ovector[8] : ovector[10] - 1;
        int rest = len - start;
        patch = palloc(rest + 1);
        memcpy(patch, str + start, rest);
        patch[rest] = '\0';
      }
  }
  newval = make_semver64(parts, patch);
  if (patch)
    pfree(patch);
  pcre_free(re);
  return newval;
}

char* emit_semver64(semver64* version) {
    int len;
    char tmpbuf[512];
    int buf_len;
    char *buf;
    int i;
    buf_len = sizeof(tmpbuf);
    len = 0;

    for(i = 0; i < 3; i++) {
        len += snprintf(tmpbuf + len, buf_len - len, (i != 0 ? ".%" PRIu64 : "%" PRIu64),
            version->numbers[i]);
    }
    if (*version->prerel != '\0') {
        len += snprintf(
            tmpbuf + len, buf_len - len,
            "%s%s",
            ((version->prerel)[0] == '+' ? "" : "-"),
            version->prerel
        );
    }

    /* Should cover the vast majority of cases. */
    if (len < buf_len) return pstrdup(tmpbuf);

    /* Try again, this time with the known length. */
    buf = palloc(len+1);
    buf_len = sizeof(buf);
    memcpy(buf, tmpbuf, buf_len);
    return buf;
}

/*
 * Pg bindings
 */

PG_FUNCTION_INFO_V1(semver64_out);
Datum
semver64_out(PG_FUNCTION_ARGS)
{
    semver64* amount = PG_GETARG_SEMVER64_P(0);
    char *result;
    result = emit_semver64(amount);

    PG_RETURN_CSTRING(result);
}


PG_FUNCTION_INFO_V1(semver64_to_text);
Datum
semver64_to_text(PG_FUNCTION_ARGS)
{
    semver64* sv = PG_GETARG_SEMVER64_P(0);
    char* xxx = emit_semver64(sv);
    text* res = cstring_to_text(xxx);
    pfree(xxx);
    PG_RETURN_TEXT_P(res);
}

PG_FUNCTION_INFO_V1(get_semver64_major);
Datum
get_semver64_major(PG_FUNCTION_ARGS)
{
    char tmpbuf[21];
    text* res;
    semver64* sv = PG_GETARG_SEMVER64_P(0);
    snprintf(tmpbuf, sizeof(tmpbuf), "%" PRIu64, sv->numbers[0]);
    res = cstring_to_text(tmpbuf);
    PG_RETURN_CSTRING(res);
}

PG_FUNCTION_INFO_V1(get_semver64_minor);
Datum
get_semver64_minor(PG_FUNCTION_ARGS)
{
    char tmpbuf[21];
    text* res;
    semver64* sv = PG_GETARG_SEMVER64_P(0);
    snprintf(tmpbuf, sizeof(tmpbuf), "%" PRIu64, sv->numbers[1]);
    res = cstring_to_text(tmpbuf);
    PG_RETURN_CSTRING(res);

}

PG_FUNCTION_INFO_V1(get_semver64_patch);
Datum
get_semver64_patch(PG_FUNCTION_ARGS)
{
    char tmpbuf[21];
    text* res;
    semver64* sv = PG_GETARG_SEMVER64_P(0);
    snprintf(tmpbuf, sizeof(tmpbuf), "%" PRIu64, sv->numbers[2]);
    res = cstring_to_text(tmpbuf);
    PG_RETURN_CSTRING(res);
}

PG_FUNCTION_INFO_V1(get_semver64_prerelease);
Datum
get_semver64_prerelease(PG_FUNCTION_ARGS)
{
    semver64* sv = PG_GETARG_SEMVER64_P(0);
    char* prerelease = strip_meta(sv->prerel);
    text* res = cstring_to_text(prerelease);
    PG_RETURN_TEXT_P(res);
}

// add recv/send functions
PG_FUNCTION_INFO_V1(semver64_recv);

Datum
semver64_recv(PG_FUNCTION_ARGS)
{
    StringInfo  buf = (StringInfo) PG_GETARG_POINTER(0);

    semver64* sv;
    uint64_t parts[] = {-1, -1, -1};

    int         nbytes;
    char        *prerel;
    parts[0] = pq_getmsgint64(buf);
    parts[1] = pq_getmsgint64(buf);
    parts[2] = pq_getmsgint64(buf);

    nbytes = buf->len - buf->cursor;
    // the meta-pre-build info should not contain the pre char '-' at the start
    prerel = (char *) pq_getmsgbytes(buf, nbytes);
    sv = make_semver64(parts, prerel);
    PG_RETURN_POINTER(sv);
}

PG_FUNCTION_INFO_V1(semver64_send);

Datum
semver64_send(PG_FUNCTION_ARGS)
{
    semver64* sv = PG_GETARG_SEMVER64_P(0);
    StringInfoData buf;
    pq_begintypsend(&buf);
    pq_sendint64(&buf, sv->numbers[0]);
    pq_sendint64(&buf, sv->numbers[1]);
    pq_sendint64(&buf, sv->numbers[2]);
    // the meta-pre-build info should not contain the pre char '-' at the start
    pq_sendbytes(&buf, (const char *)sv->prerel, strlen(sv->prerel));
    PG_RETURN_BYTEA_P(pq_endtypsend(&buf));
}

/* Remove everything at and after "+" in a pre-release suffix */
char* strip_meta(const char *str)
{
    int n = strlen(str);
    char *copy = palloc(n + 1);
    int j = 0;   // current character
    strcpy(copy, str);

    while (j < n)
    {
        /* if current character is b */
        if (str[j] == '+') {
            break;
        } else {
            copy[j] = str[j];
            j++;
        }
    }
    copy[j] = '\0';
    return copy;
}

// https://semver.org/#spec-item-11:
// Precedence for two pre-release versions with the same major, minor, and patch version MUST be determined
// by comparing each dot separated identifier from left to right until a difference is found as follows:
// identifiers consisting of only digits are compared numerically and identifiers with letters or hyphens
// are compared lexically in ASCII sort order. Numeric identifiers always have lower precedence than
// non-numeric identifiers. A larger set of pre-release fields has a higher precedence than a smaller set,
// if all of the preceding identifiers are equal. Example:
// 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0.

#define TAIL_CMP_LT -1
#define TAIL_CMP_EQ  0
#define TAIL_CMP_GT +1
#define TAIL_CMP_KO  9

int tail_cmp ( char *lhs, char *rhs ) {
  if ( !strcasecmp ( lhs, rhs ) ) return TAIL_CMP_EQ;

  char *dot = ".";
  char *l_last, *r_last;

  char *l_token = strtok_r ( lhs, dot, &l_last );
  char *r_token = strtok_r ( rhs, dot, &r_last );

  if (  l_token && !r_token ) return TAIL_CMP_LT;
  if ( !l_token &&  r_token ) return TAIL_CMP_GT;

  while ( l_token || r_token ) {
    if ( l_token && r_token ) {
      int l_numeric = isdigit ( l_token[0] );
      int r_numeric = isdigit ( r_token[0] );

      if ( l_numeric && r_numeric ) {
        int l_int = atoi ( l_token );
        int r_int = atoi ( r_token );

        if ( l_int < r_int ) return TAIL_CMP_LT;
        if ( l_int > r_int ) return TAIL_CMP_GT;
      }
      else if ( l_numeric ) {
        return TAIL_CMP_LT;
      }
      else if ( r_numeric ) {
        return TAIL_CMP_GT;
      }
      else {
        int cmp = strcasecmp ( l_token, r_token );

        if ( cmp ) return cmp > 0 ? TAIL_CMP_GT : TAIL_CMP_LT;
      }
    }
    else if ( l_token ) {
      return TAIL_CMP_GT;
    }
    else if ( r_token ) {
      return TAIL_CMP_LT;
    }

    l_token = strtok_r ( NULL, dot, &l_last );
    r_token = strtok_r ( NULL, dot, &r_last );
  }

  return TAIL_CMP_KO;
}

int prerelcmp(const char* a, const char* b)
{
    int res;
    char *ac, *bc;

    ac = strip_meta(a);
    bc = strip_meta(b);
    if (*ac == '\0' && *bc != '\0') {
        return 1;
    }
    if (*ac != '\0' && *bc == '\0') {
        return -1;
    }
    res = tail_cmp(ac, bc);
    pfree(ac);
    pfree(bc);
    return res;
}

/* comparisons */
int _semver64_cmp(semver64* a, semver64* b)
{
    int i;
    uint64_t rv, a_x, b_x;
    rv = 0;
    for (i = 0; i < 3; i++) {
        a_x = a->numbers[i];
        b_x = b->numbers[i];
        if (a_x < b_x) {
            rv = -1;
            break;
        }
        else if (a_x > b_x) {
            rv = 1;
            break;
        }
    }
    if (rv == 0) {
        rv = prerelcmp(a->prerel, b->prerel);
    }
    return rv;
}

PG_FUNCTION_INFO_V1(semver64_eq);
Datum
semver64_eq(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_BOOL(diff == 0);
}

PG_FUNCTION_INFO_V1(semver64_ne);
Datum
semver64_ne(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_BOOL(diff != 0);
}

PG_FUNCTION_INFO_V1(semver64_le);
Datum
semver64_le(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_BOOL(diff <= 0);
}

PG_FUNCTION_INFO_V1(semver64_lt);
Datum
semver64_lt(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_BOOL(diff < 0);
}

PG_FUNCTION_INFO_V1(semver64_ge);
Datum
semver64_ge(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_BOOL(diff >= 0);
}

PG_FUNCTION_INFO_V1(semver64_gt);
Datum
semver64_gt(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_BOOL(diff > 0);
}

PG_FUNCTION_INFO_V1(semver64_cmp);
Datum
semver64_cmp(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    PG_RETURN_INT32(diff);
}

/* from catalog/pg_proc.h */
#define hashtext 400
#define hashint4 450

/* so the '=' function can be 'hashes' */
PG_FUNCTION_INFO_V1(hash_semver64);
Datum
hash_semver64(PG_FUNCTION_ARGS)
{
    semver64* version = PG_GETARG_SEMVER64_P(0);
    uint32 hash = 0;
    int i;
    Datum prerel;

    if (*version->prerel != '\0') {
        prerel = CStringGetTextDatum(version->prerel);
        hash = OidFunctionCall1(hashtext, prerel);
    }
    for (i = 0; i < 3; i++) {
        hash = (hash << (7+(i<<1))) & (hash >> (25-(i<<1)));
        hash ^= OidFunctionCall1(hashint4, version->numbers[i]);
    }

    PG_RETURN_INT32(hash);
}

PG_FUNCTION_INFO_V1(semver64_larger);
Datum
semver64_larger(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    if (diff >= 0) {
        PG_RETURN_POINTER(a);
    }
    else {
        PG_RETURN_POINTER(b);
    }
}

PG_FUNCTION_INFO_V1(semver64_smaller);
Datum
semver64_smaller(PG_FUNCTION_ARGS)
{
    semver64* a = PG_GETARG_SEMVER64_P(0);
    semver64* b = PG_GETARG_SEMVER64_P(1);
    int diff = _semver64_cmp(a, b);
    if (diff <= 0) {
        PG_RETURN_POINTER(a);
    }
    else {
        PG_RETURN_POINTER(b);
    }
}

// parse_semver64(char* str, bool lax, bool throw, bool* bad)
PG_FUNCTION_INFO_V1(to_semver64);
Datum
to_semver64(PG_FUNCTION_ARGS)
{
    text* sv = PG_GETARG_TEXT_PP(0);
    semver64* newval;
    char *str = text_to_cstring(sv);
    char* patch = 0;
    int pos = 0;
    uint64_t parts[] = {0, 0, 0};
    uint64_t num;
    while(*str != '\0') {
        if (isdigit(*str)) {
            num = 0;
            while(isdigit(*str)) {
                num = (num << 1) + (num << 3) + *str++ - '0';
            }
            parts[pos++] = num;
        }
        if (*str != '\0') {
            *str++;
        }
    }
    newval = make_semver64(parts, patch);
    PG_RETURN_POINTER(newval);
}

PG_FUNCTION_INFO_V1(is_semver64);
Datum
is_semver64(PG_FUNCTION_ARGS)
{
    text* sv = PG_GETARG_TEXT_PP(0);
    bool bad = false;
    semver64* rs = parse_semver64(text_to_cstring(sv), false, &bad);
    if (rs != NULL) pfree(rs);
    PG_RETURN_BOOL(!bad);
}

/* input function: C string */
PG_FUNCTION_INFO_V1(semver64_in);
Datum
semver64_in(PG_FUNCTION_ARGS)
{
    char *str = PG_GETARG_CSTRING(0);
    bool bad = false;
    semver64 *result = parse_semver64(str, true, &bad);
    if (!result)
        PG_RETURN_NULL();

    PG_RETURN_POINTER(result);
}/* output function: C string */

PG_FUNCTION_INFO_V1(text_to_semver64);
Datum
text_to_semver64(PG_FUNCTION_ARGS)
{
    text* sv = PG_GETARG_TEXT_PP(0);
    bool bad = false;
    semver64* rs = parse_semver64(text_to_cstring(sv), true, &bad);
    PG_RETURN_POINTER(rs);
}
