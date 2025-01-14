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


#include "snes9x.h"
#include "memmap.h"
#include "cheats.h"

#include "mac-prefix.h"
#include "mac-audio.h"
#include "mac-dialog.h"
#include "mac-os.h"
#include "mac-screenshot.h"
#include "mac-stringtools.h"
#include "mac-cheatfinder.h"

#define	kCFNumBytesPop				'Size'
#define	kCFViewModeRad				'Mode'
#define	kCFCompModePop				'Math'
#define kCFCompStoredRad			'RSto'
#define	kCFCompLastRad				'RLst'
#define	kCFCompThisRad				'RThs'
#define	kCFCompValueTxt				'CTxt'
#define	kCFSearchBtn				'BSea'
#define	kCFStoreValueBtn			'BSto'
#define	kCFWatchBtn					'BWat'
#define kCFDrawerBtn				'Drwr'
#define	kCFWatchAddrTxt				'WTxt'
#define	kCFRestoreBtn				'BRes'
#define	kCFRemoveBtn				'BRem'
#define	kCFAddEntryBtn				'BAdd'
#define kCFUserPane					'Pane'
#define	kCFSheetAddrTxt				'AEad'
#define	kCFSheetCurrentValueTxt		'AEcv'
#define	kCFSheetCheetValueTxt		'AEtx'
#define	kCFSheetDescriptionTxt		'AEde'
#define	kCFSheetAddBtn				'SHTa'
#define	kCFSheetCancelBtn			'SHTc'
#define	kCFListView					'List'
#define	kCFUpperViews				'UI_T'
#define	kCFLowerViews				'UI_B'

#define kEventScrollableScrollThere	'ESST'
#define kEventCheatFinderList		'ECFL'
#define kControlListLinePart		172

#define	MAIN_MEMORY_SIZE			0x20000

#define	kCheatFinderListViewClassID	CFSTR("com.snes9x.macos.snes9x.cheatfinder")

enum
{
	kCFHexadecimal = 1,
	kCFSignedDecimal,
	kCFUnsignedDecimal
};

enum
{
	kCFCompWithStored = 1,
	kCFCompWithLast,
	kCFCompWithThis
};

enum
{
	kCFSearchEqual = 1,
	kCFSearchNotEqual,
	kCFSearchGreater,
	kCFSearchGreaterOrEqual,
	kCFSearchLess,
	kCFSearchLessOrEqual
};

typedef struct
{
	IBNibRef		nibRef;
	WindowRef		main;
	WindowRef		sheet;
	WindowRef		drawer;
	HIViewRef		list;
	HIViewRef		scroll;
	EventHandlerRef	sEref;
	EventHandlerUPP	sUPP;
}	WindowData;

typedef struct
{
	HIViewRef		view;
	HIPoint			originPoint;
	HISize			lineSize;
	Boolean			inFocus;
}	ListViewData;

Boolean	cfIsWatching = false;

extern SCheatData	Cheat;

static UInt8		*cfStoredRAM;
static UInt8		*cfLastRAM;
static UInt8		*cfCurrentRAM;
static UInt8		*cfStatusFlag;
static UInt32		*cfAddress;

static SInt32		cfNumRows;
static SInt32		cfListSelection;

static SInt32		cfViewMode;
static SInt32		cfCompMode;
static SInt32		cfCompWith;
static UInt32		cfViewNumBytes;
static UInt32		cfWatchAddr;
static Boolean		cfIsNewGame;
static Boolean		cfIsStored;
static Boolean		cfDrawerShow;

static int			cfListAddrColumnWidth;
static char			cfWatchTextFormat[32];
static CTFontRef	cfListLineCTFontRef;
#ifdef MAC_TIGER_PANTHER_SUPPORT
static ATSUStyle	cfListLineATSUStyle;
#endif

static HIViewID		kCheatFinderListViewID = { 'CHET', 'FNDR' };

static void CheatFinderSearch (WindowData *);
static void CheatFinderRestoreList (WindowData *);
static void CheatFinderRemoveFromList (WindowData *);
static void CheatFinderAdjustButtons (WindowData *);
static void CheatFinderBuildResultList (void);
static void CheatFinderHandleAddEntryButton (WindowData *);
static void CheatFinderMakeValueFormat (char *);
static void CheatFinderAddEntry (SInt64, char *);
static void CheatFinderBeginAddEntrySheet (WindowData *);
static void CheatFinderEndAddEntrySheet (WindowData *);
static void CheatFinderListViewScrollToThere (float, ListViewData *);
static void CheatFinderListViewDraw (CGContextRef, HIRect *, ListViewData *);
static float CheatFinderListViewSanityCheck (float, ListViewData *);
static SInt64 CheatFinderReadBytes (UInt8 *, UInt32);
static SInt64 CheatFinderGetValueEditText (ControlRef);
static Boolean CheatFinderCompare (SInt64, SInt64);
static HIViewPartCode CheatFinderListViewFindPart (EventRef, ListViewData *, SInt32 *);


void InitCheatFinder (void)
{
	cfStoredRAM  = new UInt8 [MAIN_MEMORY_SIZE + 10];
	cfLastRAM    = new UInt8 [MAIN_MEMORY_SIZE + 10];
	cfCurrentRAM = new UInt8 [MAIN_MEMORY_SIZE + 10];
	cfStatusFlag = new UInt8 [MAIN_MEMORY_SIZE + 10];
	cfAddress    = new UInt32[MAIN_MEMORY_SIZE + 10];

	if (!cfStoredRAM || !cfLastRAM || !cfCurrentRAM || !cfStatusFlag || !cfAddress)
		QuitWithFatalError(@"cheatfinder 01");

	memset(cfCurrentRAM, 0x00, MAIN_MEMORY_SIZE + 10);

	cfViewMode     = kCFUnsignedDecimal;
	cfViewNumBytes = 2;
	cfCompMode     = kCFSearchEqual;
	cfCompWith     = kCFCompWithThis;

    cfListLineCTFontRef = CTFontCreateWithName(CFSTR("Lucida Sans Typewriter Regular"), 11.0f, NULL);
    if (cfListLineCTFontRef == NULL)
    {
        cfListLineCTFontRef = CTFontCreateWithName(CFSTR("Menlo"), 11.0f, NULL);
        if (cfListLineCTFontRef == NULL)
        {
            cfListLineCTFontRef = CTFontCreateWithName(CFSTR("Monaco"), 11.0f, NULL);
            if (cfListLineCTFontRef == NULL)
                QuitWithFatalError(@"cheatfinder 02");
        }
    }
}

void ResetCheatFinder (void)
{
	memset(cfStoredRAM,  0x00, MAIN_MEMORY_SIZE);
	memset(cfLastRAM,    0x00, MAIN_MEMORY_SIZE);
	memset(cfStatusFlag, 0xFF, MAIN_MEMORY_SIZE);

	cfWatchAddr  = 0;
	cfIsNewGame  = true;
	cfIsWatching = false;
	cfIsStored   = false;
	cfDrawerShow = false;

	CheatFinderMakeValueFormat(cfWatchTextFormat);
}

void DeinitCheatFinder (void)
{
    CFRelease(cfListLineCTFontRef);

	delete [] cfStoredRAM;
	delete [] cfLastRAM;
	delete [] cfCurrentRAM;
	delete [] cfStatusFlag;
	delete [] cfAddress;
}

void CheatFinder (void)
{
//    static HIObjectClassRef    cfListViewClass = NULL;
//
//    OSStatus                err;
//    HIViewRef                ctl;
//    HIViewID                cid;
//    char                    num[256];
//    WindowData                cf;
//    EventHandlerRef            wEref, pEref;
//    EventHandlerUPP            wUPP, pUPP;
//    EventTypeSpec            wEvents[] = { { kEventClassCommand,    kEventCommandProcess           },
//                                          { kEventClassCommand,    kEventCommandUpdateStatus      },
//                                          { kEventClassWindow,     kEventWindowClose              } },
//                            pEvents[] = { { kEventClassControl,    kEventControlDraw              } },
//                            cEvents[] = { { kEventClassHIObject,   kEventHIObjectConstruct        },
//                                          { kEventClassHIObject,   kEventHIObjectInitialize       },
//                                          { kEventClassHIObject,   kEventHIObjectDestruct         },
//                                          { kEventClassScrollable, kEventScrollableGetInfo        },
//                                          { kEventClassScrollable, kEventScrollableScrollTo       },
//                                          { kEventCheatFinderList, kEventScrollableScrollThere    },
//                                          { kEventClassControl,    kEventControlHitTest           },
//                                          { kEventClassControl,    kEventControlTrack             },
//                                          { kEventClassControl,    kEventControlValueFieldChanged },
//                                          { kEventClassControl,    kEventControlDraw              } };
//
//    if (!cartOpen)
//        return;
//
//    err = CreateNibReference(kMacS9XCFString, &(cf.nibRef));
//    if (err == noErr)
//    {
//        err = CreateWindowFromNib(cf.nibRef, CFSTR("CheatFinder"), &(cf.main));
//        if (err == noErr)
//        {
//            err = CreateWindowFromNib(cf.nibRef, CFSTR("CFDrawer"), &(cf.drawer));
//            if (err == noErr)
//            {
//                memcpy(cfCurrentRAM, Memory.RAM, MAIN_MEMORY_SIZE);
//                CheatFinderBuildResultList();
//
//                err = noErr;
//                if (!cfListViewClass)
//                    err = HIObjectRegisterSubclass(kCheatFinderListViewClassID, kHIViewClassID, 0, CheatFinderListViewHandler, GetEventTypeCount(cEvents), cEvents, NULL, &cfListViewClass);
//                if (err == noErr)
//                {
//                    HIObjectRef        hiObject;
//                    HIViewRef        userpane, scrollview, listview, imageview, root;
//                    HILayoutInfo    layoutinfo;
//                    HIRect            frame;
//                    HISize            minSize;
//                    CGImageRef        image;
//                    Rect            rct;
//                    float            pich;
//
//                    GetWindowBounds(cf.main, kWindowContentRgn, &rct);
//
//                    minSize.width  = (float) (rct.right  - rct.left);
//                    minSize.height = (float) (rct.bottom - rct.top );
//                    err = SetWindowResizeLimits(cf.main, &minSize, NULL);
//
//                    root = HIViewGetRoot(cf.main);
//                    cid.id = 0;
//                    cid.signature = kCFUserPane;
//                    HIViewFindByID(root, cid, &userpane);
//
//                    err = HIScrollViewCreate(kHIScrollViewOptionsVertScroll, &scrollview);
//                    HIViewAddSubview(userpane, scrollview);
//                    HIViewGetBounds(userpane, &frame);
//                    cfListAddrColumnWidth = (int) (frame.size.width * 0.4);
//                    frame.origin.y    += 16.0f;
//                    frame.size.height -= 16.0f;
//                    frame = CGRectInset(frame, 1.0f, 1.0f);
//                    HIViewSetFrame(scrollview, &frame);
//                    HIViewSetVisible(scrollview, true);
//                    cf.scroll = scrollview;
//
//                    layoutinfo.version = kHILayoutInfoVersionZero;
//                    HIViewGetLayoutInfo(scrollview, &layoutinfo);
//
//                    layoutinfo.binding.top.toView    = userpane;
//                    layoutinfo.binding.top.kind      = kHILayoutBindTop;
//                    layoutinfo.binding.bottom.toView = userpane;
//                    layoutinfo.binding.bottom.kind   = kHILayoutBindBottom;
//                    layoutinfo.binding.left.toView   = userpane;
//                    layoutinfo.binding.left.kind     = kHILayoutBindLeft;
//                    layoutinfo.binding.right.toView  = userpane;
//                    layoutinfo.binding.right.kind    = kHILayoutBindRight;
//                    HIViewSetLayoutInfo(scrollview, &layoutinfo);
//
//                    err = HIObjectCreate(kCheatFinderListViewClassID, NULL, &hiObject);
//                    listview = (HIViewRef) hiObject;
//                    HIViewAddSubview(scrollview, listview);
//                    SetControl32BitMinimum(listview, 1);
//                    SetControl32BitMaximum(listview, cfNumRows);
//                    SetControl32BitValue(listview, 1);
//                    HIViewSetVisible(listview, true);
//                    cf.list = listview;
//
//                    cid.signature = kCFNumBytesPop;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfViewNumBytes);
//
//                    cid.signature = kCFViewModeRad;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfViewMode);
//
//                    cid.signature = kCFCompModePop;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfCompMode);
//
//                    if (cfIsNewGame || (!cfIsStored && (cfCompWith == kCFCompWithStored)))
//                        cfCompWith = kCFCompWithThis;
//
//                    cid.signature = kCFCompStoredRad;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfCompWith == kCFCompWithStored);
//                    if (cfIsStored)
//                        ActivateControl(ctl);
//                    else
//                        DeactivateControl(ctl);
//
//                    cid.signature = kCFCompLastRad;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfCompWith == kCFCompWithLast);
//                    if (!cfIsNewGame)
//                        ActivateControl(ctl);
//                    else
//                        DeactivateControl(ctl);
//
//                    cid.signature = kCFCompThisRad;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfCompWith == kCFCompWithThis);
//
//                    cid.signature = kCFCompValueTxt;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetEditTextCFString(ctl, CFSTR(""), false);
//                    err = SetKeyboardFocus(cf.main, ctl, kControlFocusNextPart);
//
//                    cid.signature = kCFWatchBtn;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfIsWatching);
//
//                    cid.signature = kCFDrawerBtn;
//                    HIViewFindByID(root, cid, &ctl);
//                    SetControl32BitValue(ctl, cfDrawerShow);
//
//                    cid.signature = kCFWatchAddrTxt;
//                    HIViewFindByID(root, cid, &ctl);
//                    if (cfIsWatching)
//                    {
//                        sprintf(num, "%06lX", cfWatchAddr + 0x7E0000);
//                        SetStaticTextCStr(ctl, num, false);
//                    }
//                    else
//                        SetStaticTextCFString(ctl, CFSTR(""), false);
//
//                    CheatFinderAdjustButtons(&cf);
//
//                    pUPP = NewEventHandlerUPP(CheatFinderListFrameEventHandler);
//                    err = InstallControlEventHandler(userpane, pUPP, GetEventTypeCount(pEvents), pEvents, (void *) userpane, &pEref);
//
//                    wUPP = NewEventHandlerUPP(CheatFinderWindowEventHandler);
//                    err = InstallWindowEventHandler (cf.main,  wUPP, GetEventTypeCount(wEvents), wEvents, (void *) &cf,      &wEref);
//
//                    pich = (float) (IPPU.RenderedScreenHeight >> ((IPPU.RenderedScreenHeight > 256) ? 1 : 0));
//
//                    err = SetDrawerParent(cf.drawer, cf.main);
//                    err = SetDrawerOffsets(cf.drawer, 0.0f, (float) ((rct.bottom - rct.top) - (pich + 37)));
//
//                    image = CreateGameScreenCGImage();
//                    if (image)
//                    {
//                        err = HIImageViewCreate(image, &imageview);
//                        if (err == noErr)
//                        {
//                            HIViewFindByID(HIViewGetRoot(cf.drawer), kHIViewWindowContentID, &ctl);
//
//                            HIViewAddSubview(ctl, imageview);
//                            HIImageViewSetOpaque(imageview, false);
//                            HIImageViewSetScaleToFit(imageview, true);
//                            HIViewSetVisible(imageview, true);
//
//                            frame.origin.x = 8.0f;
//                            frame.origin.y = 8.0f;
//                            frame.size.width  = (float) SNES_WIDTH;
//                            frame.size.height = pich;
//                            HIViewSetFrame(imageview, &frame);
//                        }
//                    }
//
//                    MoveWindowPosition(cf.main, kWindowCheatFinder, true);
//                    ShowWindow(cf.main);
//
//                    if (cfDrawerShow)
//                        err = OpenDrawer(cf.drawer, kWindowEdgeDefault, false);
//
//                    err = RunAppModalLoopForWindow(cf.main);
//
//                    HideWindow(cf.main);
//                    SaveWindowPosition(cf.main, kWindowCheatFinder);
//
//                    err = RemoveEventHandler(pEref);
//                    DisposeEventHandlerUPP(pUPP);
//
//                    err = RemoveEventHandler(wEref);
//                    DisposeEventHandlerUPP(wUPP);
//
//                    if (image)
//                        CGImageRelease(image);
//                }
//
//                CFRelease(cf.drawer);
//            }
//
//            CFRelease(cf.main);
//        }
//
//        DisposeNibReference(cf.nibRef);
//
//        memcpy(cfLastRAM, Memory.RAM, MAIN_MEMORY_SIZE);
//        cfIsNewGame = false;
//    }
}

static SInt64 CheatFinderReadBytes (UInt8 *mem, UInt32 addr)
{
	switch (cfViewMode)
	{
		case kCFSignedDecimal:
		{
			switch (cfViewNumBytes)
			{
				case 1:	return ((SInt64) (SInt8)      mem[addr]);
				case 2:	return ((SInt64) (SInt16)    (mem[addr] | (mem[addr + 1] << 8)));
				case 4:	return ((SInt64) (SInt32)    (mem[addr] | (mem[addr + 1] << 8) | (mem[addr + 2] << 16) | (mem[addr + 3] << 24)));
				case 3:	return ((SInt64) (((SInt32) ((mem[addr] | (mem[addr + 1] << 8) | (mem[addr + 2] << 16)) << 8)) >> 8));
			}

			break;
		}

		case kCFUnsignedDecimal:
		case kCFHexadecimal:
		{
			switch (cfViewNumBytes)
			{
				case 1:	return ((SInt64) (UInt8)      mem[addr]);
				case 2:	return ((SInt64) (UInt16)    (mem[addr] | (mem[addr + 1] << 8)));
				case 3:	return ((SInt64) (UInt32)    (mem[addr] | (mem[addr + 1] << 8) | (mem[addr + 2] << 16)));
				case 4:	return ((SInt64) (UInt32)    (mem[addr] | (mem[addr + 1] << 8) | (mem[addr + 2] << 16) | (mem[addr + 3] << 24)));
			}

			break;
		}
	}

	return (0);
}


static SInt64 CheatFinderGetValueEditText (HIViewRef control)
{
	SInt64	result = 0;
	UInt32	uvalue;
	SInt32	svalue;
	char	num[256];

	GetEditTextCStr(control, num);
	if (num[0] == 0)
	{
		SetEditTextCFString(control, CFSTR("0"), true);
		return (0);
	}

	switch (cfViewMode)
	{
		case kCFSignedDecimal:
		{
			if (sscanf(num, "%ld", &svalue) == 1)
			{
				switch (cfViewNumBytes)
				{
					case 1:
					{
						if (svalue >  127)
						{
							svalue =  127;
							SetEditTextCFString(control, CFSTR("127"), true);
						}
						else
						if (svalue < -128)
						{
							svalue = -128;
							SetEditTextCFString(control, CFSTR("-128"), true);
						}

						break;
					}

					case 2:
					{
						if (svalue >  32767)
						{
							svalue =  32767;
							SetEditTextCFString(control, CFSTR("32767"), true);
						}
						else
						if (svalue < -32768)
						{
							svalue = -32768;
							SetEditTextCFString(control, CFSTR("-32768"), true);
						}

						break;
					}

					case 3:
					{
						if (svalue >  8388607)
						{
							svalue =  8388607;
							SetEditTextCFString(control, CFSTR("8388607"), true);
						}
						else
						if (svalue < -8388608)
						{
							svalue = -8388608;
							SetEditTextCFString(control, CFSTR("-8388608"), true);
						}

						break;
					}
				}
			}
			else
			{
				svalue = 0;
				SetEditTextCFString(control, CFSTR("0"), true);
			}

			result = (SInt64) svalue;

			break;
		}

		case kCFUnsignedDecimal:
		{
			if (sscanf(num, "%lu", &uvalue) == 1)
			{
				switch (cfViewNumBytes)
				{
					case 1:
					{
						if (uvalue > 255)
						{
							uvalue = 255;
							SetEditTextCFString(control, CFSTR("255"), true);
						}

						break;
					}

					case 2:
					{
						if (uvalue > 65535)
						{
							uvalue = 65535;
							SetEditTextCFString(control, CFSTR("65535"), true);
						}

						break;
					}

					case 3:
					{
						if (uvalue > 16777215)
						{
							uvalue = 16777215;
							SetEditTextCFString(control, CFSTR("16777215"), true);
						}

						break;
					}
				}
			}
			else
			{
				uvalue = 0;
				SetEditTextCFString(control, CFSTR("0"), true);
			}

			result = (SInt64) uvalue;

			break;
		}

		case kCFHexadecimal:
		{
			if (sscanf(num, "%lx", &uvalue) == 1)
			{
				switch (cfViewNumBytes)
				{
					case 1:
					{
						if (uvalue > 0xFF)
						{
							uvalue = 0xFF;
							SetEditTextCFString(control, CFSTR("FF"), true);
						}

						break;
					}

					case 2:
					{
						if (uvalue > 0xFFFF)
						{
							uvalue = 0xFFFF;
							SetEditTextCFString(control, CFSTR("FFFF"), true);
						}

						break;
					}

					case 3:
					{
						if (uvalue > 0xFFFFFF)
						{
							uvalue = 0xFFFFFF;
							SetEditTextCFString(control, CFSTR("FFFFFF"), true);
						}

						break;
					}
				}
			}
			else
			{
				uvalue = 0;
				SetEditTextCFString(control, CFSTR("0"), true);
			}

			result = (SInt64) uvalue;

			break;
		}
	}

	return (result);
}

static void CheatFinderSearch (WindowData *cf)
{
//    SInt64    cmpvalue;
//    UInt8    *mem;
//
//    if (cfCompWith == kCFCompWithThis)
//    {
//        HIViewRef    ctl;
//        HIViewID    cid = { kCFCompValueTxt, 0 };
//
//        HIViewFindByID(HIViewGetRoot(cf->main), cid, &ctl);
//        cmpvalue = CheatFinderGetValueEditText(ctl);
//
//        for (int i = 0; i < cfNumRows; i++)
//            if (!CheatFinderCompare(CheatFinderReadBytes(cfCurrentRAM, cfAddress[i]), cmpvalue))
//                cfStatusFlag[cfAddress[i]] = 0;
//    }
//    else
//    {
//        mem = (cfCompWith == kCFCompWithStored) ? cfStoredRAM : cfLastRAM;
//
//        for (int i = 0; i < cfNumRows; i++)
//            if (!CheatFinderCompare(CheatFinderReadBytes(cfCurrentRAM, cfAddress[i]), CheatFinderReadBytes(mem, cfAddress[i])))
//                cfStatusFlag[cfAddress[i]] = 0;
//    }
//
//    CheatFinderBuildResultList();
//
//    SetControl32BitMaximum(cf->list, cfNumRows);
//    SetControl32BitValue(cf->list, 1);
}

static Boolean CheatFinderCompare (SInt64 ramvalue, SInt64 cmpvalue)
{
	switch (cfCompMode)
	{
		case kCFSearchEqual:			return (ramvalue == cmpvalue);
		case kCFSearchNotEqual:			return (ramvalue != cmpvalue);
		case kCFSearchGreater:			return (ramvalue >  cmpvalue);
		case kCFSearchGreaterOrEqual:	return (ramvalue >= cmpvalue);
		case kCFSearchLess:				return (ramvalue <  cmpvalue);
		case kCFSearchLessOrEqual:		return (ramvalue <= cmpvalue);
	}

	return (false);
}

static void CheatFinderBuildResultList (void)
{
	cfNumRows = 0;

	for (int i = 0; i < MAIN_MEMORY_SIZE; i++)
	{
		if (cfStatusFlag[i] == 0xFF)
		{
			cfAddress[cfNumRows] = i;
			cfNumRows++;
		}
	}

	cfListSelection = 0;
}

static void CheatFinderAdjustButtons (WindowData *cf)
{
//    HIViewRef    ctl, root;
//    HIViewID    cid;
//
//    cid.id = 0;
//    root = HIViewGetRoot(cf->main);
//
//    if (cfNumRows > 0)
//    {
//        cid.signature = kCFAddEntryBtn;
//        HIViewFindByID(root, cid, &ctl);
//        ActivateControl(ctl);
//
//        cid.signature = kCFRemoveBtn;
//        HIViewFindByID(root, cid, &ctl);
//        ActivateControl(ctl);
//
//        cid.signature = kCFWatchBtn;
//        HIViewFindByID(root, cid, &ctl);
//        ActivateControl(ctl);
//    }
//    else
//    {
//        cid.signature = kCFAddEntryBtn;
//        HIViewFindByID(root, cid, &ctl);
//        DeactivateControl(ctl);
//
//        cid.signature = kCFRemoveBtn;
//        HIViewFindByID(root, cid, &ctl);
//        DeactivateControl(ctl);
//
//        if (!cfIsWatching)
//        {
//            cid.signature = kCFWatchBtn;
//            HIViewFindByID(root, cid, &ctl);
//            DeactivateControl(ctl);
//        }
//    }
}

static void CheatFinderRemoveFromList (WindowData *cf)
{
//    if (cfNumRows > 0)
//    {
//        cfStatusFlag[cfAddress[cfListSelection]] = 0;
//
//        if (cfNumRows == 1)
//        {
//            cfNumRows = 0;
//
//            SetControl32BitMaximum(cf->list, 0);
//            SetControl32BitValue(cf->list, 1);
//        }
//        else
//        {
//            for (int i = cfListSelection; i < cfNumRows - 1; i++)
//                cfAddress[i] = cfAddress[i + 1];
//
//            cfNumRows--;
//            if (cfListSelection >= cfNumRows)
//                cfListSelection = cfNumRows - 1;
//
//            SetControl32BitMaximum(cf->list, cfNumRows);
//            SetControl32BitValue(cf->list, cfListSelection + 1);
//        }
//    }
}

static void CheatFinderRestoreList (WindowData *cf)
{
//    memset(cfStatusFlag, 0xFF, MAIN_MEMORY_SIZE);
//    CheatFinderBuildResultList();
//
//    SetControl32BitMaximum(cf->list, cfNumRows);
//    SetControl32BitValue(cf->list, 1);
}

static void CheatFinderMakeValueFormat (char *text)
{
//    switch (cfViewMode)
//    {
//        case kCFSignedDecimal:
//        case kCFUnsignedDecimal:
//        {
//            strcpy(text, "%lld");
//            break;
//        }
//
//        case kCFHexadecimal:
//        {
//            sprintf(text, "%%0%lullX", cfViewNumBytes * 2);
//            break;
//        }
//    }
}

void CheatFinderDrawWatchAddr (void)
{
//    static char    code[256];
//
//    uint16        *basePtr;
//    int            len;
//
//    sprintf(code, cfWatchTextFormat, CheatFinderReadBytes(Memory.RAM, cfWatchAddr));
//
//    basePtr = GFX.Screen + 1;
//    len = strlen(code);
//
//    for (int i = 0; i < len; i++)
//    {
//        S9xDisplayChar(basePtr, code[i]);
//        basePtr += (8 - 1);
//    }
}

static void CheatFinderHandleAddEntryButton (WindowData *cf)
{
//    if (cfAddress[cfListSelection] > (0x20000 - cfViewNumBytes))
//        NSBeep();
//    else
//    if (Cheat.g.size() + cfViewNumBytes > MAC_MAX_CHEATS)
//        AppearanceAlert(kAlertCautionAlert, kS9xMacAlertCFCantAddEntry, kS9xMacAlertCFCantAddEntryHint);
//    else
//        CheatFinderBeginAddEntrySheet(cf);
}

static void CheatFinderBeginAddEntrySheet (WindowData *cf)
{
//    OSStatus        err;
//    HIViewRef        ctl, root;
//    HIViewID        cid;
//    UInt32            addr;
//    char            str[256], form[256];
//    EventTypeSpec    sEvents[] = { { kEventClassCommand, kEventCommandProcess      },
//                                  { kEventClassCommand, kEventCommandUpdateStatus } };
//
//    err = CreateWindowFromNib(cf->nibRef, CFSTR("CFAddEntry"), &(cf->sheet));
//    if (err == noErr)
//    {
//        addr = cfAddress[cfListSelection];
//
//        root = HIViewGetRoot(cf->sheet);
//        cid.id = 0;
//
//        cid.signature = kCFSheetAddrTxt;
//        HIViewFindByID(root, cid, &ctl);
//        sprintf(str, "%06lX", addr + 0x7E0000);
//        SetStaticTextCStr(ctl, str, false);
//
//        cid.signature = kCFSheetCurrentValueTxt;
//        HIViewFindByID(root, cid, &ctl);
//        CheatFinderMakeValueFormat(form);
//        sprintf(str, form, CheatFinderReadBytes(cfCurrentRAM, addr));
//        SetStaticTextCStr(ctl, str, false);
//
//        cid.signature = kCFSheetCheetValueTxt;
//        HIViewFindByID(root, cid, &ctl);
//        SetEditTextCStr(ctl, str, false);
//
//        err = ClearKeyboardFocus(cf->sheet);
//        err = SetKeyboardFocus(cf->sheet, ctl, kControlFocusNextPart);
//
//        cid.signature = kCFSheetDescriptionTxt;
//        HIViewFindByID(root, cid, &ctl);
//        sprintf(str, "%06lX-%06lX", addr + 0x7E0000, addr + cfViewNumBytes - 1 + 0x7E0000);
//        SetStaticTextCStr(ctl, str, false);
//
//        cf->sUPP = NewEventHandlerUPP(CheatFinderSheetEventHandler);
//        err = InstallWindowEventHandler(cf->sheet, cf->sUPP, GetEventTypeCount(sEvents), sEvents, (void *) cf, &(cf->sEref));
//
//        err = ShowSheetWindow(cf->sheet, cf->main);
//    }
}

static void CheatFinderEndAddEntrySheet (WindowData *cf)
{
//    if (cf->sheet)
//    {
//        OSStatus    err;
//
//        err = HideSheetWindow(cf->sheet);
//
//        err = RemoveEventHandler(cf->sEref);
//        DisposeEventHandlerUPP(cf->sUPP);
//
//        CFRelease(cf->sheet);
//    }
}


static void CheatFinderAddEntry (SInt64 value, char *description)
{
	UInt32	addr, v;

	addr = cfAddress[cfListSelection];
	v = (UInt32) (SInt32) value;

	for (unsigned int i = 0; i < cfViewNumBytes; i++)
	{
		char code[10];
		snprintf(code, 10, "%x=%x", addr + i + 0x7E0000, (UInt8) ((v & (0x000000FF << (i * 8))) >> (i * 8)));
		int index = S9xAddCheatGroup(description, code);
		if(index >= 0)
			S9xEnableCheatGroup(index);
	}
}

static void CheatFinderListViewDraw (CGContextRef ctx, HIRect *bounds, ListViewData *myData)
{
//    static Boolean    init = true;
//
//    if (systemVersion >= 0x1050)
//    {
//        static CGRect            aRct, vRct;
//
//        CTLineRef                line;
//        CFDictionaryRef            attr;
//        CFAttributedStringRef    astr;
//        CFStringRef                str;
//        HIRect                    lineBounds;
//        SInt32                    start, end, val, max;
//        float                    ax, vx, y, f;
//        char                    format[32], t1[64], t2[64];
//
//        CFStringRef                keys[] = { kCTFontAttributeName, kCTForegroundColorAttributeName        };
//        CFTypeRef                bval[] = { cfListLineCTFontRef,  CGColorGetConstantColor(kCGColorBlack) },
//                                wval[] = { cfListLineCTFontRef,  CGColorGetConstantColor(kCGColorWhite) };
//
//        CheatFinderMakeValueFormat(format);
//
//        start = (SInt32)  (myData->originPoint.y / myData->lineSize.height);
//        end   = (SInt32) ((myData->originPoint.y + bounds->size.height) / myData->lineSize.height) + 1;
//
//        y = start * myData->lineSize.height - myData->originPoint.y;
//
//        lineBounds = *bounds;
//        lineBounds.size.height = myData->lineSize.height;
//        lineBounds.origin.y = y;
//
//        val = GetControl32BitValue(myData->view) - 1;
//        max = GetControl32BitMaximum(myData->view);
//
//        attr = CFDictionaryCreate(kCFAllocatorDefault, (const void **) &keys, (const void **) &bval, sizeof(keys) / sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
//
//        CGContextSetTextMatrix(ctx, CGAffineTransformIdentity);
//
//        if (init)
//        {
//            CGContextSetTextPosition(ctx, 0.0f, 0.0f);
//
//            astr = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("FFFFFF"), attr);
//            line = CTLineCreateWithAttributedString(astr);
//            aRct = CTLineGetImageBounds(line, ctx);
//            CFRelease(line);
//            CFRelease(astr);
//
//            astr = CFAttributedStringCreate(kCFAllocatorDefault, CFSTR("FFFFFFFFFFF"), attr);
//            line = CTLineCreateWithAttributedString(astr);
//            vRct = CTLineGetImageBounds(line, ctx);
//            CFRelease(line);
//            CFRelease(astr);
//
//            init = false;
//        }
//
//        ax = (float) (int) (((float) cfListAddrColumnWidth - 2.0 - aRct.size.width) / 2.0);
//        vx = (float) (int) (lineBounds.origin.x + lineBounds.size.width - vRct.size.width - 12.0);
//
//        for (int i = start; i <= end; i++)
//        {
//            if ((i == val) && cfNumRows)
//                CGContextSetRGBFillColor(ctx,  59.0f / 256.0f, 124.0f / 256.0f, 212.0f / 256.0f, 1.0f);
//            else
//            if ((i - start) % 2 == 0)
//                CGContextSetRGBFillColor(ctx, 256.0f / 256.0f, 256.0f / 256.0f, 256.0f / 256.0f, 1.0f);
//            else
//                CGContextSetRGBFillColor(ctx, 237.0f / 256.0f, 244.0f / 256.0f, 254.0f / 256.0f, 1.0f);
//
//            CGContextFillRect(ctx, lineBounds);
//
//            if (i < max)
//            {
//                CGContextScaleCTM(ctx, 1, -1);
//
//                if (i == val)
//                {
//                    CFRelease(attr);
//                    attr = CFDictionaryCreate(kCFAllocatorDefault, (const void **) &keys, (const void **) &wval, sizeof(keys) / sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
//                }
//
//                f = -(y + 12.0f);
//
//                sprintf(t1, "%06lX", cfAddress[i] + 0x7E0000);
//                str = CFStringCreateWithCString(kCFAllocatorDefault, t1, kCFStringEncodingUTF8);
//                astr = CFAttributedStringCreate(kCFAllocatorDefault, str, attr);
//                line = CTLineCreateWithAttributedString(astr);
//                CGContextSetTextPosition(ctx, ax, f);
//                CTLineDraw(line, ctx);
//                CFRelease(line);
//                CFRelease(astr);
//                CFRelease(str);
//
//                sprintf(t2, format, CheatFinderReadBytes(cfCurrentRAM, cfAddress[i]));
//                strcpy(t1, "            ");
//                t1[11 - strlen(t2)] = 0;
//                strcat(t1, t2);
//                str = CFStringCreateWithCString(kCFAllocatorDefault, t1, kCFStringEncodingUTF8);
//                astr = CFAttributedStringCreate(kCFAllocatorDefault, str, attr);
//                line = CTLineCreateWithAttributedString(astr);
//                CGContextSetTextPosition(ctx, vx, f);
//                CTLineDraw(line, ctx);
//                CFRelease(line);
//                CFRelease(astr);
//                CFRelease(str);
//
//                CGContextScaleCTM(ctx, 1, -1);
//
//                if (i == val)
//                {
//                    CFRelease(attr);
//                    attr = CFDictionaryCreate(kCFAllocatorDefault, (const void **) &keys, (const void **) &bval, sizeof(keys) / sizeof(keys[0]), &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
//                }
//            }
//
//            y += myData->lineSize.height;
//            lineBounds.origin.y += myData->lineSize.height;
//        }
//
//        CFRelease(attr);
//    }
//#ifdef MAC_TIGER_PANTHER_SUPPORT
//    else
//    {
//        static Rect        aRect = { 0, 0, 0, 0 }, vRect = { 0, 0, 0, 0 };
//
//        OSStatus        err;
//        ATSUTextLayout    layout;
//        HIRect            lineBounds;
//        UniCharCount    runLength[1], len;
//        SInt32            start, end, val, max;
//        Fixed            ax, vx, f;
//        float            y;
//        UniChar            unistr[64];
//        char            format[32], t1[64], t2[64];
//
//        ATSUAttributeTag        theTags[]   = { kATSUCGContextTag    };
//        ByteCount                theSizes[]  = { sizeof(CGContextRef) };
//        ATSUAttributeValuePtr    theValues[] = { &ctx                 };
//
//        CheatFinderMakeValueFormat(format);
//
//        start = (SInt32)  (myData->originPoint.y / myData->lineSize.height);
//        end   = (SInt32) ((myData->originPoint.y + bounds->size.height) / myData->lineSize.height) + 1;
//
//        y = start * myData->lineSize.height - myData->originPoint.y;
//
//        lineBounds = *bounds;
//        lineBounds.size.height = myData->lineSize.height;
//        lineBounds.origin.y = y;
//
//        val = GetControl32BitValue(myData->view) - 1;
//        max = GetControl32BitMaximum(myData->view);
//
//        if (init)
//        {
//            f = Long2Fix(0);
//            for (unsigned int n = 0; n < 11; n++)
//                unistr[n] = 'F';
//
//            len = runLength[0] = 6;
//            err = ATSUCreateTextLayoutWithTextPtr(unistr, kATSUFromTextBeginning, kATSUToTextEnd, len, 1, runLength, &cfListLineATSUStyle, &layout);
//            err = ATSUSetLayoutControls(layout, sizeof(theTags) / sizeof(theTags[0]), theTags, theSizes, theValues);
//            err = ATSUMeasureTextImage(layout, kATSUFromTextBeginning, kATSUToTextEnd, f, f, &aRect);
//            err = ATSUDisposeTextLayout(layout);
//
//            len = runLength[0] = 11;
//            err = ATSUCreateTextLayoutWithTextPtr(unistr, kATSUFromTextBeginning, kATSUToTextEnd, len, 1, runLength, &cfListLineATSUStyle, &layout);
//            err = ATSUSetLayoutControls(layout, sizeof(theTags) / sizeof(theTags[0]), theTags, theSizes, theValues);
//            err = ATSUMeasureTextImage(layout, kATSUFromTextBeginning, kATSUToTextEnd, f, f, &vRect);
//            err = ATSUDisposeTextLayout(layout);
//
//            init = false;
//        }
//
//        ax = Long2Fix((cfListAddrColumnWidth - 2 - (aRect.right - aRect.left)) >> 1);
//        vx = Long2Fix((int) (lineBounds.origin.x + lineBounds.size.width) - (vRect.right - vRect.left) - 13);
//
//        for (int i = start; i <= end; i++)
//        {
//            if ((i == val) && cfNumRows)
//                CGContextSetRGBFillColor(ctx,  59.0f / 256.0f, 124.0f / 256.0f, 212.0f / 256.0f, 1.0f);
//            else
//            if ((i - start) % 2 == 0)
//                CGContextSetRGBFillColor(ctx, 256.0f / 256.0f, 256.0f / 256.0f, 256.0f / 256.0f, 1.0f);
//            else
//                CGContextSetRGBFillColor(ctx, 237.0f / 256.0f, 244.0f / 256.0f, 254.0f / 256.0f, 1.0f);
//
//            CGContextFillRect(ctx, lineBounds);
//
//            if (i < max)
//            {
//                CGContextScaleCTM(ctx, 1, -1);
//
//                if (i == val)
//                    CGContextSetRGBFillColor(ctx, 1.0f, 1.0f, 1.0f, 1.0f);
//                else
//                    CGContextSetRGBFillColor(ctx, 0.0f, 0.0f, 0.0f, 1.0f);
//
//                f = Long2Fix(-((int) y + 12));
//
//                sprintf(t1, "%06lX", cfAddress[i] + 0x7E0000);
//                len = runLength[0] = strlen(t1);
//                for (unsigned int n = 0; n < len; n++)
//                    unistr[n] = t1[n];
//                err = ATSUCreateTextLayoutWithTextPtr(unistr, kATSUFromTextBeginning, kATSUToTextEnd, len, 1, runLength, &cfListLineATSUStyle, &layout);
//                err = ATSUSetLayoutControls(layout, sizeof(theTags) / sizeof(theTags[0]), theTags, theSizes, theValues);
//                err = ATSUDrawText(layout, kATSUFromTextBeginning, kATSUToTextEnd, ax, f);
//                err = ATSUDisposeTextLayout(layout);
//
//                sprintf(t2, format, CheatFinderReadBytes(cfCurrentRAM, cfAddress[i]));
//                strcpy(t1, "            ");
//                t1[11 - strlen(t2)] = 0;
//                strcat(t1, t2);
//                len = runLength[0] = strlen(t1);
//                for (unsigned int n = 0; n < len; n++)
//                    unistr[n] = t1[n];
//                err = ATSUCreateTextLayoutWithTextPtr(unistr, kATSUFromTextBeginning, kATSUToTextEnd, len, 1, runLength, &cfListLineATSUStyle, &layout);
//                err = ATSUSetLayoutControls(layout, sizeof(theTags) / sizeof(theTags[0]), theTags, theSizes, theValues);
//                err = ATSUDrawText(layout, kATSUFromTextBeginning, kATSUToTextEnd, vx, f);
//                err = ATSUDisposeTextLayout(layout);
//
//                CGContextScaleCTM(ctx, 1, -1);
//            }
//
//            y += myData->lineSize.height;
//            lineBounds.origin.y += myData->lineSize.height;
//        }
//    }
//#endif
}

static HIViewPartCode CheatFinderListViewFindPart (EventRef inEvent, ListViewData *myData, SInt32 *whichLine)
{
//    OSStatus        err;
//    HIViewPartCode    part;
//    HIPoint            hipt;
//    SInt32            start, line;
//    float            y;
//
//    part = kControlNoPart;
//
//    start = (SInt32) (myData->originPoint.y / myData->lineSize.height);
//    y = start * myData->lineSize.height - myData->originPoint.y;
//
//    err = GetEventParameter(inEvent, kEventParamMouseLocation, typeHIPoint, NULL, sizeof(hipt), NULL, &hipt);
//    if (err == noErr)
//    {
//        line = start + (SInt32) ((hipt.y - y - 1) / myData->lineSize.height) + 1;
//
//        if (line <= GetControl32BitMaximum(myData->view))
//            part = kControlListLinePart;
//
//        if (whichLine != NULL)
//            *whichLine = line;
//    }
//
//    return (part);
    return 0;
}

static float CheatFinderListViewSanityCheck (float where, ListViewData *myData)
{
	HIRect	bounds;
	HISize	imageSize;

//    HIViewGetBounds(myData->view, &bounds);
//    imageSize = myData->lineSize;
//    imageSize.height *= GetControl32BitMaximum(myData->view);

	if (where + bounds.size.height > imageSize.height)
		where = imageSize.height - bounds.size.height;
	if (where < 0)
		where = 0;

	return (where);
}

static void CheatFinderListViewScrollToThere (float where, ListViewData *myData)
{
	OSStatus	err;
	EventRef	theEvent;
	HIPoint		whereP = { 0.0f, where };

	err = CreateEvent(kCFAllocatorDefault, kEventCheatFinderList, kEventScrollableScrollThere, GetCurrentEventTime(), kEventAttributeUserEvent, &theEvent);
	if (err == noErr)
	{
		err = SetEventParameter(theEvent, kEventParamOrigin, typeHIPoint, sizeof(whereP), &whereP);
//        if (err == noErr)
//            err = SendEventToEventTarget(theEvent, GetControlEventTarget(myData->view));

		ReleaseEvent(theEvent);
	}
}
