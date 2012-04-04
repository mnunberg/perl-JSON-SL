#include "perl-jsonsl.h"
#include "jsonxs_inline.h"

/*
 * JSON::SL, JSON::SL::Boolean
 */
#define MY_CXT_KEY "JSON::SL::_guts" XS_VERSION

typedef struct {
    PLJSONSL* quick;
    HV *stash_obj;
    HV *stash_boolean;
    HV *stash_tuba;
} my_cxt_t;
START_MY_CXT

static int PLJSONSL_Escape_Table_dfl[0x80];
#define ESCTBL PLJSONSL_Escape_Table_dfl
#define ESCAPE_TABLE_DFL_INIT \
    memset(ESCTBL, 0, sizeof(ESCTBL)); \
    ESCTBL['"'] = 1; \
    ESCTBL['\\'] = 1; \
    ESCTBL['/'] = 1; \
    ESCTBL['b'] = 1; \
    ESCTBL['n'] = 1; \
    ESCTBL['r'] = 1; \
    ESCTBL['f'] = 1; \
    ESCTBL['u'] = 1; \
    ESCTBL['t'] = 1;


#ifdef PLJSONSL_HAVE_HV_COMMON
#define pljsonsl_hv_storeget_he(pjsn, hv, buf, len, value) \
    hv_common((HV*)(hv), NULL, buf, len, 0, HV_FETCH_ISSTORE, value, 0)

#define pljsonsl_hv_delete_okey(pjsn, hv, buf, len, flags, hash) \
    hv_common((HV*)(hv), NULL, buf, len, 0, HV_DELETE|flags, NULL, hash)
#define PLJSONSL_INIT_KSV(...)
#define PLJSONSL_DESTROY_KSV(...)

#else
/* probably very dangerous, but the beginning of hv_store_common
 * looks quite simple...
 */

#define CLOBBER_PV(sv,buf,len) \
    SvCUR_set(sv, len); \
    SvPVX(sv) = buf;
#define UNCLOBBER_PV(sv) \
    SvCUR_set(sv, 0); \
    SvPVX(sv) = NULL;

#define PLJSONSL_INIT_KSV(pjsn) \
    pjsn->ksv = newSV(16); \
    pjsn->ksv_origpv = SvPVX(pjsn->ksv); \
    SvLEN_set(pjsn->ksv, 0); \
    SvPOK_on(pjsn->ksv);

#define PLJSONSL_DESTROY_KSV(pjsn) \
        CLOBBER_PV(pjsn->ksv, pjsn->ksv_origpv, 0); \
        SvREFCNT_dec(pjsn->ksv);

#define pljsonsl_hv_storeget_he(...) \
        pljsonsl_hv_storeget_he_THX(aTHX_ __VA_ARGS__)
static HE*
pljsonsl_hv_storeget_he_THX(pTHX_
                          PLJSONSL *pjsn,
                          HV *hv,
                          const char *buf,
                          size_t len, SV *value)
{
    HE *ret;
    CLOBBER_PV(pjsn->ksv, buf, len);
    ret = hv_store_ent(hv, pjsn->ksv, value, 0);
    UNCLOBBER_PV(pjsn->ksv);
    return ret;
}

#define pljsonsl_hv_delete_okey(...) \
        pljsonsl_hv_delete_okey_THX(aTHX_ __VA_ARGS__)
static void
pljsonsl_hv_delete_okey_THX(pTHX_
                          PLJSONSL *pjsn,
                          HV *hv,
                          const char *buf,
                          size_t len,
                          int flags,
                          U32 hash)
{
    CLOBBER_PV(pjsn->ksv, buf, len);
    (void)hv_delete_ent(hv, pjsn->ksv, flags, hash);
    UNCLOBBER_PV(pjsn->ksv);
}

/* fill in for HeUTF8 */
#warning "Using our own HeUTF8 as HeKUTF8"
#define HeUTF8(he) HeKUTF8(he)

#endif /* HAVE_HV_COMMON */


#define GET_STATE_BUFFER(pjsn, pos) \
    (char*)(SvPVX(pjsn->buf) + (pos - pjsn->pos_min_valid))

/**
 * This function will try and determine if the current
 * item is a matched result (which should be returned to
 * the user).
 * If this is a complete match, the SV (along with relevant info)
 * will be pushed to the result stack and return true. Returns
 * false otherwise.
 */
#define object_mkresult(...) object_mkresult_THX(aTHX_ __VA_ARGS__)
static inline int
object_mkresult_THX(pTHX_
                    PLJSONSL *pjsn,
                    struct jsonsl_state_st *parent,
                    struct jsonsl_state_st *child)
{
#define STORE_INFO(b, v) \
    (void)hv_stores(info_hv, PLJSONSL_INFO_KEY_##b, v)
    HV *info_hv;

    if (pjsn->options.object_drip == 0 &&
        (child->matchres != JSONSL_MATCH_COMPLETE || child->type == JSONSL_T_HKEY)) {
        return 0;
    }

    info_hv = newHV();
    if (SvTYPE(child->sv) == SVt_PVHV || SvTYPE(child->sv) == SVt_PVAV) {
        STORE_INFO(VALUE, newRV_noinc(child->sv));
    } else {
        STORE_INFO(VALUE, child->sv);
    }

    if (pjsn->options.noqstr == 0 && pjsn->options.object_drip == 0) {
        STORE_INFO(QUERY, newSVpvn_share(child->matchjpr->orig,
                                         child->matchjpr->norig, 0));
    }

    if (pjsn->options.nopath == 0) {
        SV *pathstr;
        int ii;
        pathstr = newSVpvs("/");
        for (ii = 2; ii <= (child->level); ii++) {
            struct jsonsl_state_st *cur = pjsn->jsn->stack + ii;
            struct jsonsl_state_st *prev = jsonsl_last_state(pjsn->jsn, cur);
            if (prev->type == JSONSL_T_LIST) {
                sv_catpvf(pathstr, "%d/", cur->u_loc.idx);
            } else {
                char *kbuf;
                STRLEN klen;
                assert(cur->u_loc.key);
                kbuf = HePV(cur->u_loc.key, klen);
                sv_catpvn(pathstr, kbuf, klen);
                sv_catpvs(pathstr, "/");
                if (HeUTF8(cur->u_loc.key)) {
                    SvUTF8_on(pathstr);
                }
            }
        }
        /* Trim the trailing '/' from the path string */
        if (SvCUR(pathstr) != 1) {
            SvCUR_set(pathstr, SvCUR(pathstr)-1);
        }
        STORE_INFO(PATH, pathstr);
    }

    /**
     * For the sake of allowing inspection of the object tree, array
     * and hash types are always added to their parents, even if they
     * are a complete match to be removed from the stack.
     */
    if (parent && parent->sv) {
        SvREADONLY_off(parent->sv);
        SvREFCNT_inc_simple_void_NN(child->sv);
        if (parent->type == JSONSL_T_LIST) {
            av_pop((AV*)parent->sv);
        } else {
            char *kbuf;
            STRLEN klen;
            kbuf = HePV(child->u_loc.key, klen);
            SvREADONLY_off(HeVAL(child->u_loc.key));
            pljsonsl_hv_delete_okey(pjsn, parent->sv,
                                  kbuf, klen,
                                  G_DISCARD,
                                  HeHASH(child->u_loc.key));
            /* for perls with hv_common, the above should be a macro for this: */
#if 0
            hv_common((HV*)parent->sv,
                      NULL,
                      kbuf, klen,
                      0,
                      HV_DELETE|G_DISCARD,
                      NULL,
                      HeHASH(child->u_loc.key));
#endif
            child->u_loc.key = NULL;
        }

        SvREADONLY_on(parent->sv);
        SvREADONLY_off(child->sv);
    }

    av_push(pjsn->results, newRV_noinc((SV*)info_hv));
    return 1;
#undef STORE_INFO
}

#define process_special(...) process_special_THX(aTHX_ __VA_ARGS__)
static inline void
process_special_THX(pTHX_
                    PLJSONSL *pjsn,
                    struct jsonsl_state_st *state)
{
    SV *newsv;
    char *buf = GET_STATE_BUFFER(pjsn, state->pos_begin);

#define MAKE_BOOLEAN_BLESSED_IV(v) \
    { SV *newiv = newSViv(v); newsv = newRV_noinc(newiv); sv_bless(newsv, pjsn->stash_boolean); } \

    int ndigits;



    switch (state->special_flags) {
    case JSONSL_SPECIALf_TRUE:
        if (state->pos_cur - state->pos_begin != 4) {
            die("Expected 'true'");
        }
        MAKE_BOOLEAN_BLESSED_IV(1);
        break;
    case JSONSL_SPECIALf_FALSE: {
        if (state->pos_cur - state->pos_begin != 5) {
            die("Expected 'false'");
        }
        MAKE_BOOLEAN_BLESSED_IV(0);
        break;
    }

    case JSONSL_SPECIALf_NULL:
        if (state->pos_cur - state->pos_begin != 4) {
            die("Expected 'null'");
        }
        newsv = &PL_sv_undef;
        break;

        /* Simple signed/unsigned numbers, no exponents or fractions to worry about */
    case JSONSL_SPECIALf_UNSIGNED:
        ndigits = state->pos_cur - state->pos_begin;
        if (ndigits == 1) {
            newsv = newSVuv(state->nelem);
            break;
        } /* else, ndigits > 1 */
        if (*buf == '0') {
            die("JSON::SL - Malformed number (leading zero for non-fraction)");
        }
        if (ndigits < UV_DIG) {
            newsv = newSVuv(state->nelem);
            break;
        } /* else, potential overflow */
        newsv = jsonxs_inline_process_number(buf);
        break;

    case JSONSL_SPECIALf_SIGNED:
        ndigits = (state->pos_cur - state->pos_begin)-1;
        if (ndigits == 0) {
            die("JSON::SL - Found lone '-'");
        }
        if (buf[1] == '0') {
            die("JSON::SL - Malformed number (zero after '-'");
        }

        if (ndigits < (IV_DIG-1)) {
            newsv = newSViv(-((IV)state->nelem));
            break;
        } /*else */
        newsv = jsonxs_inline_process_number(buf);
        break;



    default:
        if (state->special_flags & (JSONSL_SPECIALf_FLOAT|JSONSL_SPECIALf_EXPONENT)) {
            newsv = jsonxs_inline_process_number(buf);
            break;
        }
        warn("Buffer is %p", buf);
        warn("Length is %lu", state->pos_cur - state->pos_begin);
        warn("Special flag is %d", state->special_flags);
        die("WTF!");
        break;
    }

    if (newsv == NULL) {
        newsv = &PL_sv_undef;
    }
    state->sv = newsv;
    return;
}

/**
 * This is called to clean up any quotes, and possibly
 * handle \u-escapes in the future
 */
#define process_string(...) process_string_THX(aTHX_ __VA_ARGS__)
static void
process_string_THX(pTHX_
                   PLJSONSL* pjsn,
                   struct jsonsl_state_st *state)
{
    SV *retsv;
    char *buf = GET_STATE_BUFFER(pjsn, state->pos_begin);
    size_t buflen;
    buf++;
    buflen = (state->pos_cur - state->pos_begin) - 1;
    if (state->nescapes == 0) {
        retsv = newSVpvn(buf, buflen);
    } else {
        jsonsl_error_t err;
        jsonsl_special_t flags;
        size_t newlen;
        retsv = newSV(buflen);
        SvPOK_only(retsv);
        newlen = jsonsl_util_unescape_ex(buf,
                                         SvPVX(retsv),
                                         buflen,
                                         pjsn->escape_table,
                                         &flags,
                                         &err, NULL);
        if (!newlen) {
            SvREFCNT_dec(retsv);
            die("Could not unescape string: %s", jsonsl_strerror(err));
        }
        /* Shrink the buffer to the effective new size */
        SvCUR_set(retsv, newlen);
        if (flags & JSONSL_SPECIALf_NONASCII) {
            SvUTF8_on(retsv);
        }
    }

    state->sv = retsv;
    if (pjsn->options.utf8) {
        SvUTF8_on(state->sv);
    }

}

/**
 * Because we only want to maintain 'complete' elements, for
 * strings we ensure that their SVs do not get created until
 * the entire string is done (as a partial string would
 * not be of much use to the user anyway).
 * The opposite is true of hashes and arrays, which we create
 * immediately.
 */
static void body_push_callback(jsonsl_t jsn,
                               jsonsl_action_t action,
                               struct jsonsl_state_st *state,
                               const char *at)
{
    struct jsonsl_state_st *parent;
    SV *newsv;
    char *mkey;
    size_t mnkey;
    PLJSONSL *pjsn = (PLJSONSL*)jsn->data;
    PLJSONSL_dTHX(pjsn);

    /* Reset the position first */

    pjsn->keep_pos = state->pos_begin;
    parent = jsonsl_last_state(jsn, state);
    /* Here we set up parent positioning variables.. */

    if (parent->type == JSONSL_T_OBJECT) {
        if (state->type == JSONSL_T_HKEY) {
            return;
        }
        assert(pjsn->curhk);
        mkey = HeKEY(pjsn->curhk);
        mnkey = HeKLEN(pjsn->curhk);
        /**
         * Set the HE of our current value to the current HK, and then
         * remove curhk's visibility.
         */
        state->u_loc.key = pjsn->curhk;
        pjsn->curhk = NULL;
    } else {
        state->u_loc.idx = parent->nelem - 1;
        mkey = NULL;
        mnkey = state->u_loc.idx;
    }

    if (parent->matchres == JSONSL_MATCH_POSSIBLE) {
        state->matchjpr = jsonsl_jpr_match_state(jsn, state, mkey, mnkey,
                                                 &state->matchres);
    }

    /**
     * Ignore warnings about uninitialized newsv variable.
     */
    if (!JSONSL_STATE_IS_CONTAINER(state)) {
        return; /* nothing more to do here. String types are added at POP */
    }

    if (state->type == JSONSL_T_OBJECT) {
        newsv = (SV*)newHV();
    } else if (state->type == JSONSL_T_LIST) {
        newsv = (SV*)newAV();
    } else {
        die("WTF");
    }

    SvREADONLY_on(newsv);
    if (parent->type == JSONSL_T_LIST) {
        SvREADONLY_off(parent->sv);
        av_push((AV*)parent->sv, newRV_noinc(newsv));
        SvREADONLY_on(parent->sv);
    } else {
        /* we have the HE. */
        HeVAL(state->u_loc.key) = newRV_noinc(newsv);
        SvREADONLY_on(HeVAL(state->u_loc.key));
    }

    state->sv = newsv;
}

/**
 * Creates a new HE*. We use this HE later on using HeVAL to assign the value.
 */

#define create_hk(...) create_hk_THX(aTHX_ __VA_ARGS__)
static void
create_hk_THX(pTHX_ PLJSONSL *pjsn,
              struct jsonsl_state_st *state,
              struct jsonsl_state_st *parent)
{
    assert(pjsn->curhk == NULL);
    char *buf = GET_STATE_BUFFER(pjsn, state->pos_begin);
    STRLEN len = (state->pos_cur - state->pos_begin)-1;
    buf++;

    SvREADONLY_off(parent->sv);

    if (state->nescapes) {
        /* we have escapes within a key. rare, but allowable. No choice
         * but to allocate a new buffer for it
         */
        process_string(pjsn, state);
        pjsn->curhk = hv_store_ent((HV*)parent->sv, state->sv, &PL_sv_undef, 0);
        SvREFCNT_dec(state->sv);
        state->sv = NULL;
    } else {

        /**
         * Fast path, no copying to new SV.
         * We need to store &PL_sv_undef first to fool hv_common
         * into thinking we're not doing anything special. Then
         * we do fancy
         */
        pjsn->curhk = pljsonsl_hv_storeget_he(pjsn,
                                            parent->sv,
                                            buf, len,
                                            &PL_sv_undef);
        /* which is really this: */
#if 0
        pjsn->curhk = hv_common((HV*)parent->sv, /* HV*/
                                NULL, /* keysv */
                                buf, len,
                                0, /* flags */
                                HV_FETCH_ISSTORE, /*action*/
                                &PL_sv_undef, /*value*/
                                0);
#endif
        if (pjsn->options.utf8 ||
                state->special_flags == JSONSL_SPECIALf_NONASCII) {
            HEK_UTF8_on(HeKEY_hek(pjsn->curhk));
        }

    }

    HeVAL(pjsn->curhk) = &PL_sv_placeholder;
    SvREADONLY_on(parent->sv);
}

/* forward-declare initial state handler */
static void initial_callback(jsonsl_t jsn,
                             jsonsl_action_t action,
                             struct jsonsl_state_st *state,
                             const char *at);

/**
 * In this callback we ensure to clean up our strings and push it
 * into the parent SV
 */
static void body_pop_callback(jsonsl_t jsn,
                              jsonsl_action_t action,
                              struct jsonsl_state_st *state,
                              const char *at)
{
    /* Ending of an element */
    struct jsonsl_state_st *parent = jsonsl_last_state(jsn, state);
    register PLJSONSL *pjsn = (PLJSONSL*)jsn->data;
    PLJSONSL_dTHX(pjsn);
    register jsonsl_type_t state_type = state->type;

#define INSERT_STRING \
    if (parent && object_mkresult(pjsn, parent, state) == 0) { \
        SvREADONLY_off(parent->sv); \
        if (parent->type == JSONSL_T_OBJECT) { \
            assert(state->u_loc.key); \
            HeVAL(state->u_loc.key) = state->sv; \
        } else { \
            av_push((AV*)parent->sv, state->sv); \
        } \
        SvREADONLY_on(parent->sv); \
    }

    if (state_type == JSONSL_T_STRING) {
        process_string(pjsn, state);
        INSERT_STRING;
    } else if (state_type == JSONSL_T_HKEY) {
        assert(parent->type == JSONSL_T_OBJECT);
        create_hk(pjsn, state, parent);
    } else if (state_type == JSONSL_T_SPECIAL) {
        assert(state->special_flags);
        process_special(pjsn, state);
        INSERT_STRING;
    } else {
        SvREADONLY_off(state->sv);
        object_mkresult(pjsn, parent, state);
    }

    #undef INSERT_STRING

    if (state->sv == pjsn->root && pjsn->njprs == 0) {
        if (!pjsn->options.object_drip) {
            av_push(pjsn->results, newRV_noinc(pjsn->root));
        } /* otherwise, already pushed */
        pjsn->root = NULL;
        jsn->action_callback_PUSH = initial_callback;
    }

    state->u_loc.idx = -1;
    state->sv = NULL;
    pjsn->keep_pos = 0;

}

static int error_callback(jsonsl_t jsn,
                           jsonsl_error_t err,
                           struct jsonsl_state_st *state,
                           char *at)
{
    PLJSONSL *pjsn = (PLJSONSL*)jsn->data;
    PLJSONSL_dTHX(pjsn);
    /**
     * TODO: allow option for user-defined recovery function
     */

    die("JSON::SL - Got error %s at position %lu", jsonsl_strerror(err), jsn->pos);
    return 0;
}

static void initial_callback(jsonsl_t jsn,
                             jsonsl_action_t action,
                             struct jsonsl_state_st *state,
                             const char *at)
{
    PLJSONSL *pjsn = (PLJSONSL*)jsn->data;
    PLJSONSL_dTHX(pjsn);

    assert(action == JSONSL_ACTION_PUSH);
    if (state->type == JSONSL_T_LIST) {
        pjsn->root = (SV*)newAV();
    } else if (state->type == JSONSL_T_OBJECT) {
        pjsn->root = (SV*)newHV();
    } else {
        die("Found type %s as root element", jsonsl_strtype(state->type));
    }

    state->sv = pjsn->root;
    jsn->action_callback = NULL;
    jsn->action_callback_PUSH = body_push_callback;
    jsn->action_callback_POP = body_pop_callback;
    jsonsl_jpr_match_state(jsn, state, NULL, 0, &state->matchres);
    /* Mark root element as read only */
    SvREADONLY_on(pjsn->root);
}

#define CHECK_MAX_SIZE(pjsn,input) \
    if (pjsn->options.max_size && SvCUR(input) > pjsn->options.max_size) { \
        die("JSON::SL - max_size is %lu, but input is %lu bytes", \
            pjsn->options.max_size, SvCUR(input)); \
    }

#define pljsonsl_feed_incr(...) pljsonsl_feed_incr_THX(aTHX_ __VA_ARGS__)
static void
pljsonsl_feed_incr_THX(pTHX_ PLJSONSL* pjsn, SV *input)
{
    size_t start_pos = pjsn->jsn->pos;
    STRLEN cur_len = SvCUR(pjsn->buf);
    pjsn->pos_min_valid = pjsn->jsn->pos - cur_len;
    if (SvUTF8(input)) {
        pjsn->options.utf8 = 1;
    }
    CHECK_MAX_SIZE(pjsn, input)
    sv_catpvn(pjsn->buf, SvPVX_const(input), SvCUR(input));
    jsonsl_feed(pjsn->jsn,
                SvPVX_const(pjsn->buf) + (SvCUR(pjsn->buf)-SvCUR(input)),
                SvCUR(input));
    /**
     * Callbacks may detect the beginning of a string, in which case
     * we need to ensure the continuity of the string. In this case
     * pos_keep is set to the position of the input stream (not the SV *input,
     * but rather jsn->pos) from which we should begin buffering data.
     *
     * Now we might need to chop. The amount of bytes to chop is the
     * difference between start_pos and the keep_pos
     * variable (if any)
     */
    if (pjsn->keep_pos == 0) {
        SvCUR_set(pjsn->buf, 0);
    } else {
        assert(pjsn->keep_pos >= start_pos);
        sv_chop(pjsn->buf, SvPVX_const(pjsn->buf) + (pjsn->keep_pos - start_pos));
    }

}

static PLJSONSL*
pljsonsl_get_and_initialize_global(pTHX)
{
    dMY_CXT;
    PLJSONSL *pjsn;
    if (MY_CXT.quick == NULL) {
        Newxz(pjsn, 1, PLJSONSL);
        pjsn->jsn = jsonsl_new(PLJSONSL_MAX_DEFAULT+1);
        pjsn->stash_boolean = MY_CXT.stash_boolean;
        pjsn->jsn->data = pjsn;
        pjsn->priv_global.is_global = 1;
        memcpy(pjsn->escape_table, ESCTBL, sizeof(ESCTBL));
        PLJSONSL_mkTHX(pjsn);
        PLJSONSL_INIT_KSV(pjsn);
        MY_CXT.quick = pjsn;
    }

    pjsn = MY_CXT.quick;
    jsonsl_reset(pjsn->jsn);
    jsonsl_enable_all_callbacks(pjsn->jsn);
    pjsn->jsn->error_callback = error_callback;
    pjsn->jsn->action_callback_PUSH = initial_callback;
    pjsn->results = (AV*)sv_2mortal((SV*)newAV());
    return pjsn;
}

#define pljsonsl_feed_oneshot(...) pljsonsl_feed_oneshot_THX(aTHX_ __VA_ARGS__)
static void
pljsonsl_feed_oneshot_THX(pTHX_ PLJSONSL* pjsn, SV *input)
{
    if (!SvPOK(input)) {
        die("Input is not a string");
    }

    if (SvUTF8(input)) {
        pjsn->options.utf8 = 1;
    }
    CHECK_MAX_SIZE(pjsn, input);
    pjsn->buf = input;
    jsonsl_feed(pjsn->jsn, SvPVX_const(input), SvCUR(input));
    pjsn->buf = NULL;
    pjsn->options.utf8 = 0;
    /* the current root is never in the result stack..
     * so mortalizing it won't hurt anyone.
     */
}

/**
 * Takes an array ref (or list?) of JSONPointer strings and converts
 * them to JPR objects. Dies on error
 */
#define pljsonsl_set_jsonpointer(...) pljsonsl_set_jsonpointer_THX(aTHX_ __VA_ARGS__)
static void
pljsonsl_set_jsonpointer_THX(pTHX_ PLJSONSL *pjsn, AV *paths)
{
    jsonsl_jpr_t *jprs;
    jsonsl_error_t err;
    int ii;
    int max = av_len(paths)+1;
    const char *diestr, *pathstr;

    if (!max) {
        die("No paths given!");
    }

    Newxz(jprs, max, jsonsl_jpr_t);

    for (ii = 0; ii < max; ii++) {
        SV **tmpsv = av_fetch(paths, ii, 0);
        if (tmpsv == NULL || SvPOK(*tmpsv) == 0) {
            diestr = "Found empty path";
            goto GT_ERR;
        }
        jprs[ii] = jsonsl_jpr_new(SvPVX_const(*tmpsv), &err);
        if (jprs[ii] == NULL) {
            pathstr = SvPVX_const(*tmpsv);
            goto GT_ERR;
        }
    }

    jsonsl_jpr_match_state_init(pjsn->jsn, jprs, max);
    pjsn->jprs = jprs;
    pjsn->njprs = max;
    return;

    GT_ERR:
    for (ii = 0; ii < max; ii++) {
        if (jprs[ii] == NULL) {
            break;
        }
        jsonsl_jpr_destroy(jprs[ii]);
    }
    Safefree(jprs);
    if (pathstr) {
        die("Couldn't convert %s to jsonpointer: %s", pathstr, jsonsl_strerror(err));
    } else {
        die(diestr);
    }
}

/**
 * JSON::SL::Tuba functions.
 * In case you haven't wondered already, 'Tuba' is a play on 'SAX'
 * The callback handlers will also mark 'regions', that is, they will
 * first invoke a 'data' callback (if applicable), and then invoke
 * their special states.
 *
 * This process is repeated again when jsonsl_feed returns, to flush any
 * remaining 'data' not parsed.
 */


#define pltuba_invoke_callback(...) pltuba_invoke_callback_THX(aTHX_ __VA_ARGS__)
static void
pltuba_invoke_callback_THX(pTHX_ PLTUBA *tuba,
                           jsonsl_action_t action,
                           pltuba_callback_type cbtype,
                           SV *mextrasv)
{
    /**
     * Make my life easy, just relay this information to Perl
     */
    dSP;
    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(tuba->selfrv);
    XPUSHs(sv_2mortal(newSViv(action)));
    XPUSHs(sv_2mortal(newSViv(cbtype & 0x7f)));
    if (mextrasv) {
        XPUSHs(sv_2mortal(mextrasv));
    }
    PUTBACK;
    call_pv(PLTUBA_HELPER_FUNC, G_DISCARD);
    FREETMPS;
    LEAVE;
}

/**
 * Flush characters between the invocation of the last callback
 * and the current one. the until argument is the end position (exclusive)
 * at which we should stop submitting 'character' data.
 */
#define pltuba_flush_characters(...) pltuba_flush_characters_THX(aTHX_ __VA_ARGS__)
static void
pltuba_flush_characters_THX(pTHX_ PLTUBA *tuba, size_t until)
{
    size_t toFlush;
    const char *buf;
    SV *chunksv;
    if (!tuba->keep_pos) {
        return;
    }

    toFlush = until - tuba->keep_pos;
    buf = GET_STATE_BUFFER(tuba, tuba->keep_pos);

    if (tuba->shift_quote) {
        buf++;
        toFlush--;
    }

    tuba->keep_pos = 0;
    tuba->shift_quote = 0;

    if (toFlush == 0) {
        return;
    }
    chunksv = newSVpvn(buf, toFlush);
    pltuba_invoke_callback(tuba,
                           JSONSL_ACTION_PUSH,
                           PLTUBA_CALLBACK_CHARACTER,
                           chunksv);
    /**
     * SV has been mortalized by the invoke_callback function
     */
}
/**
 * Push callback. This is easy because we never actually do any character
 * data here.
 */
static void
pltuba_jsonsl_push_callback(jsonsl_t jsn,
                            jsonsl_action_t action,
                            struct jsonsl_state_st *state,
                            const char *at)
{
    PLTUBA *tuba = (PLTUBA*)jsn->data;
    PLJSONSL_dTHX(tuba);
    if (state->level == 1) {
        pltuba_invoke_callback(tuba, action, PLTUBA_CALLBACK_DOCUMENT, NULL);
    }

#define X(o,c) \
    if (state->type == JSONSL_T_##o) { \
        pltuba_invoke_callback(tuba, action, PLTUBA_CALLBACK_##o, NULL); \
    }
    JSONSL_XTYPE;
#undef X
    if (!JSONSL_STATE_IS_CONTAINER(state)) {
        tuba->keep_pos = state->pos_begin;
        if (state->type & JSONSL_Tf_STRINGY) {
            tuba->shift_quote = 1;
        }
    } else {
        tuba->keep_pos = 0;
    }
}

static void
pltuba_jsonsl_pop_callback(jsonsl_t jsn,
                           jsonsl_action_t action,
                           struct jsonsl_state_st *state,
                           const char *at)
{
    PLTUBA *tuba = (PLTUBA*)jsn->data;
    PLJSONSL_dTHX(tuba);

    if ((state->type & JSONSL_Tf_STRINGY)
            || state->type == JSONSL_T_SPECIAL) {
        pltuba_flush_characters(tuba, state->pos_cur);
    }
#define X(o,c) \
    if (state->type == JSONSL_T_##o) { \
        pltuba_invoke_callback(tuba, action, PLTUBA_CALLBACK_##o, NULL); \
    }
    JSONSL_XTYPE;
#undef X
    if (state->level == 1) {
        pltuba_invoke_callback(tuba, action, PLTUBA_CALLBACK_DOCUMENT, NULL);
    }
}

static int
pltuba_jsonsl_error_callback(jsonsl_t jsn,
                             jsonsl_error_t error,
                             struct jsonsl_state_st *state,
                             char *at)
{
    /**
     * This needs special handling, as we will be receiving a return
     * value from Perl for this..
     */
    die ("Got error: %s", jsonsl_strerror(error));
    return 0;
}

#define pltuba_feed(...) pltuba_feed_THX(aTHX_ __VA_ARGS__)
static void
pltuba_feed_THX(pTHX_ PLTUBA *tuba, SV *input)
{
    if (!SvPOK(input)) {
        die("Input is not string!");
    }
    tuba->buf = input;
    tuba->pos_min_valid = tuba->jsn->pos;

    SvREADONLY_on(input);
    jsonsl_feed(tuba->jsn, SvPVX_const(input), SvCUR(input));
    if (tuba->keep_pos) {
        int old_shift = tuba->shift_quote;
        pltuba_flush_characters(tuba, tuba->jsn->pos);
        tuba->keep_pos = tuba->jsn->pos;
        tuba->shift_quote = old_shift;
    }
    SvREADONLY_off(input);
}

#define XOPTION \
    X(noqstr) \
    X(nopath) \
    X(utf8) \
    X(max_size) \
    X(object_drip)

enum {

#define X(o) \
    OPTION_IX_##o,

    OPTION_IX_begin = 0,
    XOPTION
#undef X
    OPTION_IX_NONE
};

#define REFDEC_FIELD(pjsn, fld) \
    if (pjsn->fld != NULL) { \
        SvREFCNT_dec(pjsn->fld); \
        pjsn->fld = NULL; \
    }

/**
 * XS interface.
 */

#define POPULATE_CXT \
    MY_CXT.stash_obj = gv_stashpv(PLJSONSL_CLASS_NAME, GV_ADD); \
    MY_CXT.stash_boolean = gv_stashpv(PLJSONSL_BOOLEAN_NAME, GV_ADD); \
    MY_CXT.stash_tuba = gv_stashpv(PLTUBA_CLASS_NAME, GV_ADD); \
    MY_CXT.quick = NULL;


/**
 * These two macros arrange for the contents of the result stack to be returned
 * to perlspace.
 */
#define dRESULT_VARS \
    int result_count; \
    int result_iter; \
    SV *result_sv;

#define RETURN_RESULTS(pjsn) \
    switch(GIMME_V) { \
    case G_VOID: \
        result_count = 0; \
        break; \
    case G_SCALAR: \
        result_sv = av_shift(pjsn->results); \
        if (result_sv == &PL_sv_undef) { \
            result_count = 0; \
            break; \
        } \
        XPUSHs(sv_2mortal(result_sv)); \
        result_count = 1; \
        break; \
    case G_ARRAY: \
        result_count = av_len(pjsn->results) + 1; \
        if (result_count == 0) { \
            break; \
        } \
        EXTEND(SP, result_count); \
        for (result_iter = 0; result_iter < result_count; result_iter++) { \
            result_sv = av_delete(pjsn->results, result_iter, 0); \
            /*already mortal according to av_delete*/ \
            PUSHs(result_sv); \
        } \
        av_clear(pjsn->results); \
        break; \
    default: \
        die("eh? (RETURN_RESULTS)"); \
        result_count = 0; \
        break; \
    }




MODULE = JSON::SL PACKAGE = JSON::SL PREFIX = PLJSONSL_

PROTOTYPES: DISABLED

BOOT:
{
    MY_CXT_INIT;
    POPULATE_CXT;
    ESCAPE_TABLE_DFL_INIT;
}

SV *
PLJSONSL_new(SV *pkg, ...)
    PREINIT:
    PLJSONSL *pjsn;
    SV *ptriv, *retrv;
    int levels;
    dMY_CXT;
    CODE:
    (void)pkg;
    if (items > 1) {
        if (!SvIOK(ST(1))) {
            die("Second argument (if provided) must be numeric");
        }
        levels = SvIV(ST(1));
        if (levels < 2) {
            die ("Levels must be at least 2");
        }
    } else {
        levels = PLJSONSL_MAX_DEFAULT;
    }

    Newxz(pjsn, 1, PLJSONSL);
    pjsn->jsn = jsonsl_new(levels+2);
    ptriv = newSViv(PTR2IV(pjsn));
    retrv = newRV_noinc(ptriv);
    sv_bless(retrv, MY_CXT.stash_obj);
    pjsn->buf = newSVpvn("", 0);

    jsonsl_enable_all_callbacks(pjsn->jsn);
    pjsn->jsn->action_callback = initial_callback;
    pjsn->jsn->error_callback = error_callback;
    pjsn->stash_boolean = MY_CXT.stash_boolean;
    pjsn->jsn->data = pjsn;
    pjsn->results = newAV();
    memcpy(pjsn->escape_table, ESCTBL, sizeof(ESCTBL));
    PLJSONSL_mkTHX(pjsn);
    PLJSONSL_INIT_KSV(pjsn);
    RETVAL = retrv;

    OUTPUT: RETVAL


void
PLJSONSL_set_jsonpointer(PLJSONSL *pjsn, AV *paths)
    PPCODE:
    pljsonsl_set_jsonpointer(pjsn, paths);

SV *
PLJSONSL_root(PLJSONSL *pjsn)
    CODE:
    if (pjsn->root) {
        RETVAL = newRV_inc(pjsn->root);
    } else {
        RETVAL = &PL_sv_undef;
    }
    OUTPUT: RETVAL

void
PLJSONSL__modify_readonly(PLJSONSL *pjsn, SV *ref)
    ALIAS:
    make_referrent_writeable = 1
    make_referrent_readonly = 2
    CODE:
    if (!SvROK(ref)) {
        die("Variable is not a reference!");
    }
    if (ix == 0) {
        croak_xs_usage(cv, "use make_referrent_writeable or make_referrent_readonly");
    } else if (ix == 1) {
        SvREADONLY_off(SvRV(ref));
    } else if (ix == 2) {
        SvREADONLY_on(SvRV(ref));
    }

int
PLJSONSL_referrent_is_writeable(PLJSONSL *pjsn, SV *ref)
    CODE:
    if (!SvROK(ref)) {
        die("Variable is not a reference!");
    }
    RETVAL = SvREADONLY(SvRV(ref)) == 0;
    OUTPUT: RETVAL


void
PLJSONSL_feed(PLJSONSL *pjsn, SV *input)
    ALIAS:
    incr_parse =1

    PREINIT:
    dRESULT_VARS;

    PPCODE:
    pljsonsl_feed_incr(pjsn, input);
    RETURN_RESULTS(pjsn);

void
PLJSONSL_fetch(PLJSONSL *pjsn)
    PREINIT:
    dRESULT_VARS;

    PPCODE:
    RETURN_RESULTS(pjsn);

int
PLJSONSL__option(PLJSONSL *pjsn, ...)
    ALIAS:
    utf8 = OPTION_IX_utf8
    nopath = OPTION_IX_nopath
    noqstr = OPTION_IX_noqstr
    max_size = OPTION_IX_max_size
    object_drip = OPTION_IX_object_drip

    CODE:
    RETVAL = 0;
    if (ix == 0) {
        die("Do not call this function (_options) directly");
    }
#define X(o) \
        if (ix == OPTION_IX_##o) \
            RETVAL = pjsn->options.o;
    XOPTION
#undef X
    if (items == 2) {
        int value = SvIV(ST(1));
#define X(o) if (ix == OPTION_IX_##o) pjsn->options.o = value;
        XOPTION
#undef X
    } else if (items > 2) {
        croak_xs_usage(cv, "... boolean");
    }

    OUTPUT: RETVAL

int
PLJSONSL__escape_table_chr(PLJSONSL *pjsn, U8 chrc, ...)
    CODE:
    if (chrc > 0x7f) {
        warn("Attempted to set non-ASCII escape preference");
        RETVAL = -1;
    } else {
        RETVAL = pjsn->escape_table[chrc];
        if (items == 3) {
            pjsn->escape_table[chrc] = SvIV(ST(2));
        }
    }
    OUTPUT: RETVAL

void
PLJSONSL_reset(PLJSONSL *pjsn)
    CODE:
    REFDEC_FIELD(pjsn, root);

    if (pjsn->results) {
        av_clear(pjsn->results);
    }
    if (pjsn->buf) {
        SvCUR_set(pjsn->buf, 0);
    }

    jsonsl_reset(pjsn->jsn);
    pjsn->pos_min_valid = 0;
    pjsn->keep_pos = 0;
    pjsn->curhk = NULL;
    pjsn->jsn->action_callback_PUSH = initial_callback;


void
PLJSONSL_DESTROY(PLJSONSL *pjsn)
    PREINIT:
    int ii;

    CODE:
    if (pjsn->priv_global.is_global == 0) {
        REFDEC_FIELD(pjsn, root);
        REFDEC_FIELD(pjsn, results);
        REFDEC_FIELD(pjsn, buf);
    } /* else, it's a mortal and shouldn't be freed */
    jsonsl_jpr_match_state_cleanup(pjsn->jsn);
    if (pjsn->jprs) {
        for ( ii = 0; ii < pjsn->njprs; ii++) {
            if (pjsn->jprs[ii] == NULL) {
                break;
            }
            jsonsl_jpr_destroy(pjsn->jprs[ii]);
        }
        Safefree(pjsn->jprs);
        pjsn->jprs = NULL;
    }
    if (pjsn->jsn) {
        jsonsl_destroy(pjsn->jsn);
        pjsn->jsn = NULL;
    }
    PLJSONSL_DESTROY_KSV(pjsn);
    Safefree(pjsn);

void
PLJSONSL_decode_json(SV *input)
    PREINIT:
    PLJSONSL* pjsn;
    dRESULT_VARS;

    PPCODE:
    pjsn = pljsonsl_get_and_initialize_global(aTHX);
    pljsonsl_feed_oneshot(pjsn, input);

    pjsn->curhk = NULL;
    pjsn->keep_pos = 0;
    pjsn->pos_min_valid = 0;
    pjsn->jsn->action_callback_PUSH = initial_callback;

    RETURN_RESULTS(pjsn);
    if (result_count == 0 && av_len(pjsn->results) == -1) {
        die("Incomplete JSON string?");
    }

SV *
PLJSONSL_unescape_json_string(SV *input)
    PREINIT:
    size_t origlen, newlen;
    SV *retsv = NULL;
    char *errpos;
    jsonsl_error_t err;
    jsonsl_special_t flags;

    CODE:
    if (!SvPOK(input)) {
        die("Input is not a valid string");
    }
    origlen = SvCUR(input);
    if (origlen) {
        retsv = newSV(origlen);
        newlen = jsonsl_util_unescape_ex(SvPVX_const(input), SvPVX(retsv),
                                    SvCUR(input), ESCTBL, &flags,
                                    &err, (const char**)&errpos);
        if (newlen == 0) {
            SvREFCNT_dec(retsv);
            die("Could not unescape: %s at pos %lu ('%c'..)",
                jsonsl_strerror(err),
                errpos - SvPVX_const(input),
                *errpos
            );
        }

        SvCUR_set(retsv, newlen);
        SvPOK_only(retsv);
        if (SvUTF8(input) || (flags & JSONSL_SPECIALf_NONASCII)) {
            SvUTF8_on(retsv);
        }
    } else {
        retsv = &PL_sv_undef;
    }
    RETVAL = retsv;
    OUTPUT: RETVAL



void
PLJSONSL_CLONE(PLJSONSL *pjsn)
    CODE:
    MY_CXT_CLONE;
    POPULATE_CXT;

MODULE = JSON::SL PACKAGE = JSON::SL::Tuba PREFIX = PLTUBA_

SV *
PLTUBA__initialize(const char *pkg)
    PREINIT:
    PLTUBA *tuba;
    SV *ptriv, *retrv;
    HV *subclass;
    dMY_CXT;
    CODE:
    subclass = gv_stashpv(pkg, GV_ADD);
    Newxz(tuba, 1, PLTUBA);
    tuba->jsn = jsonsl_new(PLJSONSL_MAX_DEFAULT);
    ptriv = newSViv(PTR2IV(tuba));
    retrv = newRV_noinc(ptriv);
    sv_bless(retrv, subclass);

    tuba->selfrv = newRV_inc(ptriv);
    sv_rvweaken(tuba->selfrv);
    tuba->jsn->action_callback_PUSH = pltuba_jsonsl_push_callback;
    tuba->jsn->action_callback_POP = pltuba_jsonsl_pop_callback;
    tuba->jsn->error_callback = pltuba_jsonsl_error_callback;
    jsonsl_enable_all_callbacks(tuba->jsn);
    PLJSONSL_mkTHX(tuba);
    tuba->jsn->data = tuba;
    RETVAL = retrv;

    OUTPUT: RETVAL

void
PLTUBA__parse(PLTUBA* tuba, SV *input)
    CODE:
    pltuba_feed(tuba, input);

void
PLTUBA_DESTROY(PLTUBA* tuba)
    CODE:
    jsonsl_destroy(tuba->jsn);
    tuba->jsn = NULL;
    Safefree(tuba);
