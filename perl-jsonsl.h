#ifndef PERL_JSONSL_H_
#define PERL_JSONSL_H_
#define PERL_NO_GET_CONTEXT

#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"
/**
 * Default depth limit to use, if none supplied
 */
#define PLJSONSL_MAX_DEFAULT 512

/**
 * Key names for the information returned by
 * JSONpointer results
 */
#define PLJSONSL_INFO_KEY_PATH "Path"
#define PLJSONSL_INFO_KEY_VALUE "Value"
#define PLJSONSL_INFO_KEY_QUERY "JSONPointer"

/**
 * Names of various perl globs
 */
#define PLJSONSL_CLASS_NAME "JSON::SL"
#define PLJSONSL_BOOLEAN_NAME "JSON::SL::Boolean"
#define PLJSONSL_PLACEHOLDER_NAME "JSON::SL::Placeholder"

#define PLTUBA_CLASS_NAME "JSON::SL::Tuba"
#define PLTUBA_HELPER_FUNC "JSON::SL::Tuba::_plhelper"

/**
 * Extended fields for a stack state
 * sv: the raw SV (never a reference)
 * u_loc.idx / u_loc.key: the numerical index or the HE key, depending
 *  on parent type.
 * matchres: the result of the last match
 * matchjpr: the jsonsl_jpr_t object (assuming a successful match [COMPLETE] )
 */
#define JSONSL_STATE_USER_FIELDS \
    SV *sv; \
    union { \
        int idx; \
        HE *key; \
    } u_loc; \
    int matchres; \
    int uescapes; \
    jsonsl_jpr_t matchjpr;

/**
 * We take advantage of the JSONSL_API and make all symbols
 * non-exportable
 */
#define JSONSL_API static
#include "jsonsl.h"
#include "jsonsl.c"

/**
 * For threaded perls, this stores the THX/my_perl context
 * inside the object's pl_thx field. For non threaded perls,
 * this is a nop.
 */
#ifndef tTHX
#define tTHX PerlInterpreter*
#endif

#ifdef PERL_IMPLICIT_CONTEXT
#define PLJSONSL_dTHX(pjsn) \
    pTHX = (tTHX)pjsn->pl_thx
#define PLJSONSL_mkTHX(pjsn) \
    pjsn->pl_thx = my_perl;
#else
#define PLJSONSL_dTHX(pjsn)
#define PLJSONSL_mkTHX(pjsn)
#endif /* PERL_IMPLICIT_CONTEXT */

typedef struct {
    /* Our lexer */
    jsonsl_t jsn;

    /* Root perl data structure. This is either an HV* or AV* */
    SV *root;

    /* Backlog buffer, for large strings, 'special' data, \u-escaping,
     * and other fun stuff
     */

    SV *buf;

    /* The minimum valid position. Offsets smaller than this do not
     * point to valid data anymore
     */
    size_t pos_min_valid;

    /* Minimum backlog position */
    size_t keep_pos;

    /**
     * "current" hash key. This is always a pointer to an HE* of an existing
     * hash entry, and thus should never be freed/destroyed directly.
     * This variable should only be non-null during until the next PUSH
     * callback
     */
    HE *curhk;

    /**
     * For older perls not exposing hv_common, we need a key sv.
     * make this as efficient as possible.
     */
    SV *ksv;
    char *ksv_origpv;

    /* Stash for booleans */
    HV *stash_boolean;

    /* Context (THX) for threaded perls */
    void *pl_thx;

    /**
     * Variables the user might set or be interested in (via function calls,
     * of course) are here:
     */
    struct {
        int utf8; /** Set the SvUTF8 flag */
        int nopath; /** Don't include path context in results */
        int noqstr; /** Don't include original query string in results */
        int max_size;
    } options;

    /**
     * Private options
     */
    struct {
        /* whether this is the 'global' JSON::SL object used
         * for decode_json()
         */
        int is_global;
    } priv_global;

    /**
     * If we allocate a bunch of JPR objects, keep a reference to
     * them here in order to destroy them along with ourselves.
     */
    jsonsl_jpr_t *jprs;
    size_t njprs;

    /**
     * This is the 'result stack'
     */
    AV *results;

    /**
     * Escape preferences
     */
    int escape_table[0x80];
} PLJSONSL;

typedef enum {
#define X(o,c) \
    PLTUBA_CALLBACK_##o = c,
    JSONSL_XTYPE
#undef X
    PLTUBA_CALLBACK_CHARACTER = 'c',
    PLTUBA_CALLBACK_ERROR = '!',
    PLTUBA_CALLBACK_DOCUMENT = 'D'
} pltuba_callback_type;

/**
 * This can be considered to be a 'subset' of the
 * PLJSONSL structure, but with some slight subtleties and
 * differences.
 */
typedef struct {
    jsonsl_t jsn;

    /* Position at which our last callback was invoked */
    size_t last_cb_pos;

    /* position at which the last call to feed was made */
    size_t buf_pos;

    /**
     * In cases (or actually, usually) when 'character' data is at
     * some kind of beginning, the first character is the opening
     * token itself, usually a quote. this variable defines an
     * offset (either 1 or 0) for which data is to actually be
     * delivered to the user.
     */
    ssize_t chardata_begin_offset;

    /* Buffer containing data to be dispatched */
    SV *buf;

    /* my_perl, for threaded perls */
    void *pl_thx;

    /* Options */
    struct {
        int utf8;
    } options;
} PLTUBA;

#endif /* PERL_JSONSL_H_ */
