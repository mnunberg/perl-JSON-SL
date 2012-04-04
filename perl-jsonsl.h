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

#if PERL_VERSION >= 10
#define PLJSONSL_HAVE_HV_COMMON
#else
#warning "You are using a Perl from the stone age. This code might work.."
#endif /* 5.10.0 */

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


#define PLJSONSL_COMMON_FIELDS \
    /* The lexer */ \
    jsonsl_t jsn;  \
    /* Input buffer */ \
    SV *buf; \
    /* Start position of the buffer (relative to input stream) */ \
    size_t pos_min_valid; \
    /* Position of the beginning of the earlist of (SPECIAL,STRINGY) */ \
    size_t keep_pos; \
    /* Context for threaded Perls */ \
    void *pl_thx;

typedef struct {
    PLJSONSL_COMMON_FIELDS;

    /* Root perl data structure. This is either an HV* or AV* */
    SV *root;

    /**
     * "current" hash key. This is always a pointer to an HE* of an existing
     * hash entry, and thus should never be freed/destroyed directly.
     * This variable should only be non-null during until the next PUSH
     * callback
     */
    HE *curhk;

#ifndef PLJSONSL_HAVE_HV_COMMON
    /**
     * For older perls not exposing hv_common, we need a key sv.
     * make this as efficient as possible. Instead of instantiating a new
     * SV each time for hv_fetch_ent, we keep one cached, and change its
     * PV slot as needed. I am able to do this because I have looked at 5.8's
     * implementation for the hv_* methods in hv.c and unless the hash is magical,
     * the behavior is to simply extract the PV from the SV in the beginning
     * anyway.
     */
    SV *ksv;
    char *ksv_origpv;
#endif

    /* Stash for booleans */
    HV *stash_boolean;

    /**
     * Variables the user might set or be interested in (via function calls,
     * of course) are here:
     */
    struct {
        int utf8; /** Set the SvUTF8 flag */
        int nopath; /** Don't include path context in results */
        int noqstr; /** Don't include original query string in results */
        int max_size; /** maximum input size (from JSON::XS) */
        /* ignore the jsonpointer settings and allow an 'iv-drip' of
         * objects to be returned via feed */
        int object_drip;
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
    PLJSONSL_COMMON_FIELDS;

    /* When we invoke a callback, instead of re-creating the
     * mortalized rv each time, we just keep a static reference
     * to ourselves
     */
    SV *selfrv;

    /* set by hkey and string callbacks */
    int shift_quote;

    /* Options */
    struct {
        int utf8;
    } options;
} PLTUBA;

#endif /* PERL_JSONSL_H_ */
