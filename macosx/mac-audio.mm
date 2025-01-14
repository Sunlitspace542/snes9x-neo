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
#include "apu.h"

#include <Cocoa/Cocoa.h>
#include <CoreAudio/CoreAudio.h>
#include <AudioToolbox/AudioToolbox.h>
#include <AudioUnit/AudioUnitCarbonView.h>
#include <pthread.h>
#include <semaphore.h>

#include "mac-prefix.h"
#include "mac-dialog.h"
#include "mac-musicbox.h"
#include "mac-os.h"
#include "mac-snes9x.h"
#include "mac-audio.h"

#define	kAUReverb	(1 << 0)
#define	kAUGraphEQ	(1 << 1)

int	cureffect = kAUReverb;

static AUGraph				agraph;
static AUNode				outNode, cnvNode, revNode, eqlNode;
static AudioUnit			outAU, cnvAU, revAU, eqlAU;
static pthread_mutex_t		mutex;
static UInt32				outStoredFrames, cnvStoredFrames, revStoredFrames, eqlStoredFrames, devStoredFrames;
static int16_t				*audioBuffer;
static uint32_t				audioBufferSampleCapacity;
static uint32_t				audioBufferSampleCount;
static sem_t				*soundSyncSemaphore;

static void ConnectAudioUnits (void);
static void DisconnectAudioUnits (void);
static void SaveEffectPresets (void);
static void LoadEffectPresets (void);
static void SetAudioUnitSoundFormat (void);
static void SetAudioUnitVolume (void);
static void StoreBufferFrameSize (void);
static void ChangeBufferFrameSize (void);
static void MacSamplesAvailableCallBack (void *);
static OSStatus MacAURenderCallBack (void *, AudioUnitRenderActionFlags *, const AudioTimeStamp *, UInt32, UInt32, AudioBufferList *);


void InitMacSound (void)
{
	OSStatus	err;

	err = NewAUGraph(&agraph);

	AudioComponentDescription	outdesc, cnvdesc, revdesc, eqldesc;

	outdesc.componentType         = kAudioUnitType_Output;
	outdesc.componentSubType      = kAudioUnitSubType_DefaultOutput;
	outdesc.componentManufacturer = 0;
	outdesc.componentFlags        = 0;
	outdesc.componentFlagsMask    = 0;

	cnvdesc.componentType         = kAudioUnitType_FormatConverter;
	cnvdesc.componentSubType      = kAudioUnitSubType_AUConverter;
	cnvdesc.componentManufacturer = kAudioUnitManufacturer_Apple;
	cnvdesc.componentFlags        = 0;
	cnvdesc.componentFlagsMask    = 0;

	revdesc.componentType         = kAudioUnitType_Effect;
	revdesc.componentSubType      = kAudioUnitSubType_MatrixReverb;
	revdesc.componentManufacturer = kAudioUnitManufacturer_Apple;
	revdesc.componentFlags        = 0;
	revdesc.componentFlagsMask    = 0;

	eqldesc.componentType         = kAudioUnitType_Effect;
	eqldesc.componentSubType      = kAudioUnitSubType_GraphicEQ;
	eqldesc.componentManufacturer = kAudioUnitManufacturer_Apple;
	eqldesc.componentFlags        = 0;
	eqldesc.componentFlagsMask    = 0;

	err = AUGraphAddNode(agraph, &outdesc, &outNode);
	err = AUGraphAddNode(agraph, &cnvdesc, &cnvNode);
	err = AUGraphAddNode(agraph, &revdesc, &revNode);
	err = AUGraphAddNode(agraph, &eqldesc, &eqlNode);

	err = AUGraphOpen(agraph);

	err = AUGraphNodeInfo(agraph, outNode, NULL, &outAU);
	err = AUGraphNodeInfo(agraph, cnvNode, NULL, &cnvAU);
	err = AUGraphNodeInfo(agraph, revNode, NULL, &revAU);
	err = AUGraphNodeInfo(agraph, eqlNode, NULL, &eqlAU);


	SetAudioUnitSoundFormat();
	SetAudioUnitVolume();
	StoreBufferFrameSize();
	ChangeBufferFrameSize();

	err = AUGraphInitialize(agraph);

	ConnectAudioUnits();
	LoadEffectPresets();

	pthread_mutex_init(&mutex, NULL);
	soundSyncSemaphore = sem_open("/s9x_mac_soundsync", O_CREAT, 0644, 1);
	S9xSetSamplesAvailableCallback(MacSamplesAvailableCallBack, NULL);
}

void DeinitMacSound (void)
{
	OSStatus	err;

	pthread_mutex_destroy(&mutex);
	sem_close(soundSyncSemaphore);
	sem_unlink("/s9x_mac_soundsync");
	SaveEffectPresets();
	DisconnectAudioUnits();
	err = AUGraphUninitialize(agraph);
	err = AUGraphClose(agraph);
	err = DisposeAUGraph(agraph);
}

static void SetAudioUnitSoundFormat (void)
{
	OSStatus					err;
	AudioStreamBasicDescription	format;

#ifdef __BIG_ENDIAN__
	UInt32	endian = kLinearPCMFormatFlagIsBigEndian;
#else
	UInt32	endian = 0;
#endif

	memset(&format, 0, sizeof(format));

	format.mSampleRate	     = (Float64) Settings.SoundPlaybackRate;
	format.mFormatID	     = kAudioFormatLinearPCM;
	format.mFormatFlags	     = endian | (Settings.SixteenBitSound ? kLinearPCMFormatFlagIsSignedInteger : 0);
	format.mBytesPerPacket   = 2 * (Settings.SixteenBitSound ? 2 : 1);
	format.mFramesPerPacket  = 1;
	format.mBytesPerFrame    = 2 * (Settings.SixteenBitSound ? 2 : 1);
	format.mChannelsPerFrame = 2;
	format.mBitsPerChannel   = Settings.SixteenBitSound ? 16 : 8;

	err = AudioUnitSetProperty(aueffect ? cnvAU : outAU, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format));
}

static void SetAudioUnitVolume (void)
{
	OSStatus	err;

	err = AudioUnitSetParameter(outAU, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Output, 0, (float) macSoundVolume / 100.0f, 0);
}

static void StoreBufferFrameSize (void)
{
	OSStatus					err;
	UInt32						size;
	AudioDeviceID				device;
#ifndef MAC_PANTHER_SUPPORT
	AudioObjectPropertyAddress	address;

	address.mSelector = kAudioDevicePropertyBufferFrameSize;
	address.mScope    = kAudioObjectPropertyScopeGlobal;
	address.mElement  = kAudioObjectPropertyElementMaster;
#endif

	size = sizeof(AudioDeviceID);
	err = AudioUnitGetProperty(outAU, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size);

	size = sizeof(UInt32);
#ifndef MAC_PANTHER_SUPPORT
	err = AudioObjectGetPropertyData(device, &address, 0, NULL, &size, &devStoredFrames);
#else
	err = AudioDeviceGetProperty(device, 0, false, kAudioDevicePropertyBufferFrameSize, &size, &devStoredFrames);
#endif

	size = sizeof(UInt32);
	err = AudioUnitGetProperty(outAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &outStoredFrames, &size);
	size = sizeof(UInt32);
	err = AudioUnitGetProperty(eqlAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &eqlStoredFrames, &size);
	size = sizeof(UInt32);
	err = AudioUnitGetProperty(revAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &revStoredFrames, &size);
	size = sizeof(UInt32);
	err = AudioUnitGetProperty(cnvAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &cnvStoredFrames, &size);
}

static void ChangeBufferFrameSize (void)
{
	OSStatus					err;
	UInt32						numframes, size;
	AudioDeviceID				device;
#ifndef MAC_PANTHER_SUPPORT
	AudioObjectPropertyAddress	address;

	address.mSelector = kAudioDevicePropertyBufferFrameSize;
	address.mScope    = kAudioObjectPropertyScopeGlobal;
	address.mElement  = kAudioObjectPropertyElementMaster;
#else
	AudioTimeStamp				ts;

	ts.mFlags = 0;
#endif

	size = sizeof(AudioDeviceID);
	err = AudioUnitGetProperty(outAU, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0, &device, &size);

	size = sizeof(UInt32);

	if (macSoundInterval_ms == 0)
	{
	#ifndef MAC_PANTHER_SUPPORT
		err = AudioObjectSetPropertyData(device, &address, 0, NULL, size, &devStoredFrames);
	#else
		err = AudioDeviceSetProperty(device, &ts, 0, false, kAudioDevicePropertyBufferFrameSize, size, &devStoredFrames);
	#endif

		err = AudioUnitSetProperty(outAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &outStoredFrames, size);
		err = AudioUnitSetProperty(eqlAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &eqlStoredFrames, size);
		err = AudioUnitSetProperty(revAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &revStoredFrames, size);
		err = AudioUnitSetProperty(cnvAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &cnvStoredFrames, size);

		printf("Interval: system, Frames: %d/%d/%d/%d/%d\n", (int) devStoredFrames, (int) outStoredFrames, (int) eqlStoredFrames, (int) revStoredFrames, (int) cnvStoredFrames);
	}
	else
	{
		numframes = macSoundInterval_ms * Settings.SoundPlaybackRate / 1000;

	#ifndef MAC_PANTHER_SUPPORT
		err = AudioObjectSetPropertyData(device, &address, 0, NULL, size, &numframes);
	#else
		err = AudioDeviceSetProperty(device, &ts, 0, false, kAudioDevicePropertyBufferFrameSize, size, &numframes);
	#endif

		err = AudioUnitSetProperty(outAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &numframes, size);
		err = AudioUnitSetProperty(eqlAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &numframes, size);
		err = AudioUnitSetProperty(revAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &numframes, size);
		err = AudioUnitSetProperty(cnvAU, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &numframes, size);

		printf("Interval: %dms, Frames: %d\n", (int) macSoundInterval_ms, (int) numframes);
	}
}

static void ConnectAudioUnits (void)
{
	OSStatus				err;
	AURenderCallbackStruct	callback;

	callback.inputProc       = MacAURenderCallBack;
	callback.inputProcRefCon = NULL;

    err = AUGraphSetNodeInputCallback(agraph, aueffect ? cnvNode : outNode, 0, &callback);

	if ((aueffect & kAUReverb) && (aueffect & kAUGraphEQ))
	{
		err = AUGraphConnectNodeInput(agraph, cnvNode, 0, revNode, 0);
		err = AUGraphConnectNodeInput(agraph, revNode, 0, eqlNode, 0);
		err = AUGraphConnectNodeInput(agraph, eqlNode, 0, outNode, 0);
	}
	else
	if (aueffect & kAUReverb)
	{
		err = AUGraphConnectNodeInput(agraph, cnvNode, 0, revNode, 0);
		err = AUGraphConnectNodeInput(agraph, revNode, 0, outNode, 0);
	}
	else
	if (aueffect & kAUGraphEQ)
	{
		err = AUGraphConnectNodeInput(agraph, cnvNode, 0, eqlNode, 0);
		err = AUGraphConnectNodeInput(agraph, eqlNode, 0, outNode, 0);
	}
}

static void DisconnectAudioUnits (void)
{
	OSStatus	err;

	err = AUGraphClearConnections(agraph);
}

static OSStatus MacAURenderCallBack (void *inRefCon, AudioUnitRenderActionFlags *ioActionFlags, const AudioTimeStamp *inTimeStamp, UInt32 inBusNumber, UInt32 inNumFrames, AudioBufferList *ioData)
{
	if (Settings.Mute)
	{
		memset(ioData->mBuffers[0].mData, 0, ioData->mBuffers[0].mDataByteSize);
		*ioActionFlags |= kAudioUnitRenderAction_OutputIsSilence;
	}
	else
	{
		static bool		recoverBufferUnderrun = false;
		unsigned int	samples = ioData->mBuffers[0].mDataByteSize >> 1;

		pthread_mutex_lock(&mutex);
		if (samples > audioBufferSampleCount || (recoverBufferUnderrun && audioBufferSampleCount<<1 < audioBufferSampleCapacity))
		{
			/* buffer underrun - emit silence at least 50% of buffer is filled */
			bzero(ioData->mBuffers[0].mData, samples*2);
			recoverBufferUnderrun = true;
		}
		else
		{
			recoverBufferUnderrun = false;
			memcpy(ioData->mBuffers[0].mData, audioBuffer, samples*2);
			memmove(audioBuffer, audioBuffer+samples, (audioBufferSampleCount-samples)*2);
			audioBufferSampleCount -= samples;
			sem_post(soundSyncSemaphore);
		}
		pthread_mutex_unlock(&mutex);
	}

	return (noErr);
}

static void MacSamplesAvailableCallBack (void *userData)
{
	uint32_t availableSamples = S9xGetSampleCount();
	if (Settings.DynamicRateControl)
	{
		S9xUpdateDynamicRate((audioBufferSampleCapacity-audioBufferSampleCount)*2, audioBufferSampleCapacity*2);
	}

tryLock:
	pthread_mutex_lock(&mutex);
	if (audioBufferSampleCapacity - audioBufferSampleCount < availableSamples)
	{
		/* buffer overrun */
		if (Settings.DynamicRateControl && !Settings.SoundSync)
		{
			/* for dynamic rate control, clear S9x internal buffer and do nothing */
			pthread_mutex_unlock(&mutex);
			S9xClearSamples();
			return;
		}
		if (Settings.SoundSync && !Settings.TurboMode)
		{
			/* when SoundSync is enabled, wait buffer for being drained by render callback */
			pthread_mutex_unlock(&mutex);
			sem_wait(soundSyncSemaphore);
			goto tryLock;
		}
		/* dispose samples to allocate 50% of the buffer capacity */
		uint32_t samplesToBeDisposed = availableSamples + audioBufferSampleCount - audioBufferSampleCapacity/2;
		if(samplesToBeDisposed >= audioBufferSampleCount)
		{
			audioBufferSampleCount = 0;
		}
		else
		{
			memmove(audioBuffer, audioBuffer+samplesToBeDisposed, (audioBufferSampleCount-samplesToBeDisposed)*2);
			audioBufferSampleCount = audioBufferSampleCount - samplesToBeDisposed;
		}
	}
	S9xMixSamples((uint8 *)(audioBuffer+audioBufferSampleCount), availableSamples);
	audioBufferSampleCount += availableSamples;
	pthread_mutex_unlock(&mutex);
}

static void SaveEffectPresets (void)
{
	OSStatus			err;
	AUPreset			preset;
	CFPropertyListRef	classData;
	UInt32				size;

	preset.presetNumber = -1;	// User Preset
	preset.presetName   = CFSTR("SNES9X Preset");

	err = AudioUnitSetProperty(revAU, kAudioUnitProperty_CurrentPreset, kAudioUnitScope_Global, 0, &preset, sizeof(preset));
	if (err == noErr)
	{
		size = sizeof(classData);
		err = AudioUnitGetProperty(revAU, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &classData, &size);
		if (err == noErr)
		{
			CFPreferencesSetAppValue(CFSTR("Effect_Preset_Reverb"),  classData, kCFPreferencesCurrentApplication);
			CFRelease(classData);
		}
	}

	err = AudioUnitSetProperty(eqlAU, kAudioUnitProperty_CurrentPreset, kAudioUnitScope_Global, 0, &preset, sizeof(preset));
	if (err == noErr)
	{
		size = sizeof(classData);
		err = AudioUnitGetProperty(eqlAU, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &classData, &size);
		if (err == noErr)
		{
			CFPreferencesSetAppValue(CFSTR("Effect_Preset_GraphEQ"), classData, kCFPreferencesCurrentApplication);
			CFRelease(classData);
		}
	}

	CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication);
}

static void LoadEffectPresets (void)
{
	OSStatus			err;
	CFPropertyListRef	classData;

	classData = CFPreferencesCopyAppValue(CFSTR("Effect_Preset_Reverb"),  kCFPreferencesCurrentApplication);
	if (classData)
	{
		err = AudioUnitSetProperty(revAU, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &classData, sizeof(classData));
		CFRelease(classData);
	}

	classData = CFPreferencesCopyAppValue(CFSTR("Effect_Preset_GraphEQ"), kCFPreferencesCurrentApplication);
	if (classData)
	{
		err = AudioUnitSetProperty(eqlAU, kAudioUnitProperty_ClassInfo, kAudioUnitScope_Global, 0, &classData, sizeof(classData));
		CFRelease(classData);
	}
}

void MacStartSound (void)
{
	OSStatus	err;
	Boolean		r = false;

	if (macQTRecord)
		return;

	err = AUGraphIsRunning(agraph, &r);
	if (err == noErr && r == false)
	{
		err = AUGraphStart(agraph);
		printf("AUGraph started.\n");
	}
}

void MacStopSound (void)
{
	OSStatus	err;
	Boolean		r = false;

	if (macQTRecord)
		return;

	err = AUGraphIsRunning(agraph, &r);
	if (err == noErr && r == true)
	{
		err = AUGraphStop(agraph);
		printf("AUGraph stopped.\n");
	}
}

bool8 S9xOpenSoundDevice (void)
{
	OSStatus	err;

	err = AUGraphUninitialize(agraph);

	SetAudioUnitSoundFormat();
	SetAudioUnitVolume();
	ChangeBufferFrameSize();

	err = AUGraphInitialize(agraph);

	if (audioBuffer) free(audioBuffer);
	audioBufferSampleCapacity = 2 * macSoundBuffer_ms * Settings.SoundPlaybackRate / 1000;
	audioBuffer = (int16_t *)calloc(audioBufferSampleCapacity,sizeof(int16_t));
	audioBufferSampleCount = 0;
	return (true);
}

void ConfigureSoundEffects (void)
{
//    OSStatus    err;
//    IBNibRef    nibRef;
//
//    err = CreateNibReference(kMacS9XCFString, &nibRef);
//    if (err == noErr)
//    {
//        WindowRef    uiparts;
//
//        err = CreateWindowFromNib(nibRef, CFSTR("SoundEffect"), &uiparts);
//        if (err == noErr)
//        {
//            EventHandlerUPP        eventUPP;
//            EventHandlerRef        eventHandler;
//            EventTypeSpec        event[] = { { kEventClassWindow,  kEventWindowClose         },
//                                            { kEventClassCommand, kEventCommandProcess      },
//                                            { kEventClassCommand, kEventCommandUpdateStatus } };
//            HIViewRef            ctl, userpane, contentview;
//            HIViewID            cid;
//            CFStringRef            str;
//            Rect                rct;
//            WindowAttributes    metal = 0;
//
//            cid.id = 0;
//            cid.signature = 'SfUI';
//            HIViewFindByID(HIViewGetRoot(uiparts), cid, &userpane);
//            GetWindowBounds(uiparts, kWindowContentRgn, &rct);
//
//            if (systemVersion >= 0x1040)    // AUs support compositing
//            {
//                HIRect    frame;
//
//                str = CFCopyLocalizedString(CFSTR("CreateMetalDlg"), "NO");
//                if (str)
//                {
//                    if (CFStringCompare(str, CFSTR("YES"), 0) == kCFCompareEqualTo)
//                        metal = kWindowMetalAttribute;
//
//                    CFRelease(str);
//                }
//
//                frame = CGRectMake(0.0f, 0.0f, (float) (rct.right - rct.left), (float) (rct.bottom - rct.top));
//                err = CreateNewWindow(kDocumentWindowClass, kWindowCloseBoxAttribute | kWindowCollapseBoxAttribute | kWindowStandardHandlerAttribute | kWindowCompositingAttribute | metal, &rct, &effectWRef);
//                err = HIViewFindByID(HIViewGetRoot(effectWRef), kHIViewWindowContentID, &contentview);
//                err = HIViewAddSubview(contentview, userpane);
//                err = HIViewSetFrame(userpane, &frame);
//            }
//        #ifdef MAC_PANTHER_SUPPORT
//            else
//            {
//                err = CreateNewWindow(kDocumentWindowClass, kWindowCloseBoxAttribute | kWindowCollapseBoxAttribute | kWindowStandardHandlerAttribute, &rct, &effectWRef);
//                err = CreateRootControl(effectWRef, &contentview);
//                err = EmbedControl(userpane, contentview);
//                MoveControl(userpane, 0, 0);
//            }
//        #endif
//
//            CFRelease(uiparts);
//
//            if (!metal)
//                err = SetThemeWindowBackground(effectWRef, kThemeBrushDialogBackgroundActive, false);
//
//            str = CFCopyLocalizedString(CFSTR("SoundEffectDlg"), "SoundEffect");
//            if (str)
//            {
//                err = SetWindowTitleWithCFString(effectWRef, str);
//                CFRelease(str);
//            }
//
//            if (systemVersion >= 0x1040)    // AUs support compositing
//            {
//                HILayoutInfo    layoutinfo;
//                HIViewRef        separator;
//
//                cid.signature = 'LINE';
//                err = HIViewFindByID(userpane, cid, &separator);
//
//                layoutinfo.version = kHILayoutInfoVersionZero;
//                err = HIViewGetLayoutInfo(userpane, &layoutinfo);
//
//                layoutinfo.binding.top.toView    = contentview;
//                layoutinfo.binding.top.kind      = kHILayoutBindNone;
//                layoutinfo.binding.bottom.toView = contentview;
//                layoutinfo.binding.bottom.kind   = kHILayoutBindNone;
//                layoutinfo.binding.left.toView   = contentview;
//                layoutinfo.binding.left.kind     = kHILayoutBindLeft;
//                layoutinfo.binding.right.toView  = contentview;
//                layoutinfo.binding.right.kind    = kHILayoutBindRight;
//                err = HIViewSetLayoutInfo(userpane, &layoutinfo);
//
//                layoutinfo.version = kHILayoutInfoVersionZero;
//                err = HIViewGetLayoutInfo(separator, &layoutinfo);
//
//                layoutinfo.binding.top.toView    = userpane;
//                layoutinfo.binding.top.kind      = kHILayoutBindNone;
//                layoutinfo.binding.bottom.toView = userpane;
//                layoutinfo.binding.bottom.kind   = kHILayoutBindNone;
//                layoutinfo.binding.left.toView   = userpane;
//                layoutinfo.binding.left.kind     = kHILayoutBindLeft;
//                layoutinfo.binding.right.toView  = userpane;
//                layoutinfo.binding.right.kind    = kHILayoutBindRight;
//                err = HIViewSetLayoutInfo(separator, &layoutinfo);
//            }
//
//            eventUPP = NewEventHandlerUPP(SoundEffectsEventHandler);
//            err = InstallWindowEventHandler(effectWRef, eventUPP, GetEventTypeCount(event), event, (void *) effectWRef, &eventHandler);
//
//            GetWindowBounds(effectWRef, kWindowContentRgn, &rct);
//            effectWSize.width  = (float) (rct.right  - rct.left);
//            effectWSize.height = (float) (rct.bottom - rct.top );
//
//            carbonView = NULL;
//            ReplaceAudioUnitCarbonView();
//
//            cid.signature = 'Epop';
//            HIViewFindByID(userpane, cid, &ctl);
//            switch (cureffect)
//            {
//                case kAUReverb:
//                    SetControl32BitValue(ctl, 1);
//                    break;
//
//                case kAUGraphEQ:
//                    SetControl32BitValue(ctl, 2);
//                    break;
//            }
//
//            MoveWindowPosition(effectWRef, kWindowSoundEffect, false);
//            ShowWindow(effectWRef);
//            err = RunAppModalLoopForWindow(effectWRef);
//            HideWindow(effectWRef);
//            SaveWindowPosition(effectWRef, kWindowSoundEffect);
//
//            if (carbonView)
//            {
//                err = RemoveEventHandler(carbonViewEventRef);
//                DisposeEventHandlerUPP(carbonViewEventUPP);
//                carbonViewEventRef = NULL;
//                carbonViewEventUPP = NULL;
//
//                CloseComponent(carbonView);
//                carbonView = NULL;
//            }
//
//            err = RemoveEventHandler(eventHandler);
//            DisposeEventHandlerUPP(eventUPP);
//
//            CFRelease(effectWRef);
//        }
//
//        DisposeNibReference(nibRef);
//    }
}
