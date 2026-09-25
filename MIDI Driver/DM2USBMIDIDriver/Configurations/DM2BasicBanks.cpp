/*
 *  DM2BasicNoBanks.cpp
 *  DM2USBMIDIDriver
 *
 *  Created by Joseph Mattiello on 2/17/09.
 *  Copyright 2009 Sense Networks. All rights reserved.
 *
 */

#include "DM2BasicBanks.h"
#include "DM2USBMIDI.h"
#include "DM2 Structs.h"

DM2BasicNoBanks::DM2BasicNoBanks() : DM2Configuration()
{
	/* Only bank1 is used. bank2-4 stay allocated (from the base class) because
	   PrepareOutput still routes incoming notes 16-63 to them; those notes then
	   change nothing that is displayed. */
}


#pragma mark Bottom buttons
void DM2BasicNoBanks::bottom1Clicked(DM2USBMIDIDriver * dm2)
{			
	makeBasicNote(dm2->status.bottom_1, kNOTE_BASIC_BOTTOM1BUTTON, dm2);
}
void DM2BasicNoBanks::bottom2Clicked(DM2USBMIDIDriver * dm2)
{			
	makeBasicNote(dm2->status.bottom_3, kNOTE_BASIC_BOTTOM2BUTTON, dm2);
}
void DM2BasicNoBanks::bottom3Clicked(DM2USBMIDIDriver * dm2)
{			
	makeBasicNote(dm2->status.bottom_4, kNOTE_BASIC_BOTTOM3BUTTON, dm2);
}
void DM2BasicNoBanks::bottom4Clicked(DM2USBMIDIDriver * dm2)
{			
	makeBasicNote(dm2->status.bottom_4, kNOTE_BASIC_BOTTOM4BUTTON, dm2);
}

void DM2BasicNoBanks::clearLEDAllBanks()
{
	clearLEDBank(bank1);
}

void DM2BasicNoBanks::readSettings()
{
	readBankSettings(bank1);
}
