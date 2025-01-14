/*****************************************************************************\
     Snes9x - Portable Super Nintendo Entertainment System (TM) emulator.
                This file is licensed under the Snes9x License.
   For further information, consult the LICENSE file in the root directory.
\*****************************************************************************/

/***********************************************************************************
  SNES9X for Mac OS (c) Copyright John Stiles

  Snes9x for Mac OS X

  (c) Copyright 2001 - 2011  zones
  (c) Copyright 2002 - 2005  107
  (c) Copyright 2002         PB1400c
  (c) Copyright 2004         Alexander and Sander
  (c) Copyright 2004 - 2005  Steven Seeger
  (c) Copyright 2005         Ryan Vogt
  (c) Copyright 2019         Michael Donald Buckley
 ***********************************************************************************/


#undef	READ_WORD
#undef	READ_3WORD
#undef	READ_DWORD
#undef	WRITE_WORD
#undef	WRITE_3WORD
#undef	WRITE_DWORD

#define ZLIB
#define UNZIP_SUPPORT
#define	JMA_SUPPORT
#define USE_OPENGL
#define RIGHTSHIFT_IS_SAR
#define HAVE_STDINT_H
//#define DEBUGGER

#define __MACOSX__
