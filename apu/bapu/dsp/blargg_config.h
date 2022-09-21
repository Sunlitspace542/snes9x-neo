// snes_spc 0.9.0 user configuration file. Don't replace when updating library.

// snes_spc 0.9.0
#ifndef BLARGG_CONFIG_H
#define BLARGG_CONFIG_H

// Uncomment to disable debugging checks
#if !defined(DEBUGGER) && !defined(_DEBUG)
#define NDEBUG 1
#endif

// Uncomment to enable platform-specific (and possibly non-portable) optimizations
#if !defined(__CELLOS_LV2__)
#define BLARGG_NONPORTABLE 1
#endif

// Uncomment if automatic byte-order determination doesn't work
//#define BLARGG_BIG_ENDIAN 1

// Uncomment if you get errors in the bool section of blargg_common.h
//#define BLARGG_COMPILER_HAS_BOOL 1

// Use standard config.h if present
#ifdef HAVE_CONFIG_H
	#include "config.h"
#endif

#endif
