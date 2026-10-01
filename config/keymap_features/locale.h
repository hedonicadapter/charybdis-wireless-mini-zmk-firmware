/*
 * Locale-aware symbol keycodes for shared macros/behaviors.
 *
 * Keymaps that expect OS layout Swedish define LOCALE_SV before including
 * keymap_features; all others keep US keycodes.
 *
 * keymap-drawer defines KEYMAP_DRAWER; SV_* then stay symbolic so drawer
 * configs can label them.
 */

#pragma once

#include <dt-bindings/zmk/keys.h>

#if defined(LOCALE_SV) && !defined(KEYMAP_DRAWER)
#include "keys_sv.h"

#define L_PRCNT   SV_PRCNT
#define L_ASTRK   SV_ASTRK
#define L_DOT     SV_DOT
#define L_COMMA   SV_COMMA
#define L_COLON   SV_COLON
#define L_SEMI    SV_SEMI
#define L_QMARK   SV_QMARK
#define L_EXCL    SV_EXCL
#define L_DQT     SV_DQT
#define L_BSLH    SV_BSLH
#define L_FSLH    SV_FSLH
#define L_UNDER   SV_UNDER
#define L_LPAR    SV_LPAR
#define L_RPAR    SV_RPAR
#define L_MINUS   SV_MINUS
#define L_GRAVE   SV_GRAVE
#define L_TILDE   SV_TILDE
#else
#define L_PRCNT   PRCNT
#define L_ASTRK   ASTRK
#define L_DOT     DOT
#define L_COMMA   COMMA
#define L_COLON   COLON
#define L_SEMI    SEMICOLON
#define L_QMARK   QUESTION
#define L_EXCL    EXCL
#define L_DQT     DQT
#define L_BSLH    BACKSLASH
#define L_FSLH    FSLH
#define L_UNDER   UNDER
#define L_LPAR    LPAR
#define L_RPAR    RPAR
#define L_MINUS   MINUS
#define L_GRAVE   GRAVE
#define L_TILDE   TILDE
#endif
