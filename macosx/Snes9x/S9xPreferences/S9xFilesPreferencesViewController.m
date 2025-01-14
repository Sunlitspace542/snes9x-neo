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
  (c) Copyright 2019 - 2021  Michael Donald Buckley
 ***********************************************************************************/

#import "S9xFilesPreferencesViewController.h"

@interface S9xFilesPreferencesViewController ()

@end

@implementation S9xFilesPreferencesViewController

- (instancetype)init
{
	if (self = [super initWithNibName:@"S9xFilesPreferencesViewController" bundle:nil])
	{
		self.title = NSLocalizedString(@"Files", nil);
		self.image = [NSImage imageNamed:@"files"];
	}

	return self;
}

@end
