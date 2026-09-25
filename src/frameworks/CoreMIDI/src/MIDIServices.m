#import <CoreMIDI/MIDIServices.h>

// Note: It is expected for some of these values to be assigned `nil`,
// Not sure why Apple doesn't actually assign a CFString value to these 
// variables...

/* Identification */
const CFStringRef kMIDIPropertyName = nil;
const CFStringRef kMIDIPropertyManufacturer = nil;
const CFStringRef kMIDIPropertyUniqueID = nil;

/* Presentation */
const CFStringRef kMIDIPropertyDisplayName = nil;

/* Timing */
const CFStringRef kMIDIPropertyAdvanceScheduleTimeMuSec = nil;

/* Drivers */
const CFStringRef kMIDIPropertyDriverVersion = nil;

/* Connections */
const CFStringRef kMIDIPropertyConnectionUniqueID = nil;

// Audio MIDI Setup links these property keys directly.  The MIDI device
// backend is still a stub, but the keys must be valid CFStrings for callers
// to use them in property queries and dictionaries.
#define MIDI_PROPERTY(name, value) const CFStringRef name = CFSTR(value)
MIDI_PROPERTY(kMIDIPropertyModel, "model");
MIDI_PROPERTY(kMIDIPropertyDeviceID, "deviceID");
MIDI_PROPERTY(kMIDIPropertySupportsMMC, "supportsMMC");
MIDI_PROPERTY(kMIDIPropertySupportsGeneralMIDI, "supportsGeneralMIDI");
MIDI_PROPERTY(kMIDIPropertyDriverDeviceEditorApp, "driverDeviceEditorApp");
MIDI_PROPERTY(kMIDIPropertyImage, "image");
MIDI_PROPERTY(kMIDIPropertyTransmitsMTC, "transmitsMTC");
MIDI_PROPERTY(kMIDIPropertyReceivesMTC, "receivesMTC");
MIDI_PROPERTY(kMIDIPropertyTransmitsClock, "transmitsClock");
MIDI_PROPERTY(kMIDIPropertyReceivesClock, "receivesClock");
MIDI_PROPERTY(kMIDIPropertyOffline, "offline");
MIDI_PROPERTY(kMIDIPropertyPrivate, "private");
MIDI_PROPERTY(kMIDIPropertyDriverOwner, "driverOwner");
MIDI_PROPERTY(kMIDIPropertyIsEmbeddedEntity, "isEmbeddedEntity");
MIDI_PROPERTY(kMIDIPropertyReceiveChannels, "receiveChannels");
MIDI_PROPERTY(kMIDIPropertyTransmitChannels, "transmitChannels");
MIDI_PROPERTY(kMIDIPropertyMaxReceiveChannels, "maxReceiveChannels");
MIDI_PROPERTY(kMIDIPropertyMaxTransmitChannels, "maxTransmitChannels");
MIDI_PROPERTY(kMIDIPropertyUMPCanTransmitGroupless, "umpCanTransmitGroupless");
#undef MIDI_PROPERTY
