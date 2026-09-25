#include "legacy.h"
#include <stdio.h>
#include <unistd.h>
#include <mach/mach_error.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/usb/IOUSBLib.h>

static void printRet(const char *what, IOReturn r)
{
	printf("  %s: 0x%08x (%s)\n", what, r, r == kIOReturnSuccess ? "success" : mach_error_string(r));
}

static const char *typeName(UInt8 t)
{
	switch (t) {
		case kUSBControl: return "Control";
		case kUSBIsoc: return "Isochronous";
		case kUSBBulk: return "Bulk";
		case kUSBInterrupt: return "Interrupt";
		default: return "?";
	}
}

void legacyProbe(io_service_t interfaceService)
{
	IOCFPlugInInterface **plugin = NULL;
	SInt32 score = 0;
	IOReturn r = IOCreatePlugInInterfaceForService(interfaceService, kIOUSBInterfaceUserClientTypeID,
												   kIOCFPlugInInterfaceID, &plugin, &score);
	if (r != kIOReturnSuccess || !plugin) {
		printRet("IOCreatePlugInInterfaceForService", r);
		return;
	}
	IOUSBInterfaceInterface300 **intf = NULL;
	(*plugin)->QueryInterface(plugin, CFUUIDGetUUIDBytes(kIOUSBInterfaceInterfaceID300), (LPVOID *)&intf);
	(*plugin)->Release(plugin);
	if (!intf) {
		printf("  QueryInterface(IOUSBInterfaceInterface300) failed\n");
		return;
	}

	r = (*intf)->USBInterfaceOpen(intf);
	if (r != kIOReturnSuccess) {
		printRet("USBInterfaceOpen", r);
		(*intf)->Release(intf);
		return;
	}

	// The driver calls SetAlternateInterface(0) to (re)build the pipe table; do the same.
	printRet("SetAlternateInterface(0)", (*intf)->SetAlternateInterface(intf, 0));

	UInt8 numEndpoints = 0;
	(*intf)->GetNumEndpoints(intf, &numEndpoints);
	printf("  GetNumEndpoints = %u (descriptor declares 2)\n", numEndpoints);

	for (UInt8 pipe = 1; pipe <= numEndpoints; pipe++) {
		UInt8 dir = 0, num = 0, type = 0, interval = 0;
		UInt16 maxPacket = 0;
		r = (*intf)->GetPipeProperties(intf, pipe, &dir, &num, &type, &maxPacket, &interval);
		if (r != kIOReturnSuccess) {
			char what[48];
			snprintf(what, sizeof what, "GetPipeProperties(%u)", pipe);
			printRet(what, r);
			continue;
		}
		printf("  pipe %u: endpoint %u %s %s maxPacket=%u interval=%u, status=", pipe, num,
			   dir == kUSBIn ? "IN " : "OUT", typeName(type), maxPacket, interval);
		r = (*intf)->GetPipeStatus(intf, pipe);
		printf("0x%08x\n", r);
	}

	// Exactly what dm2WriteLEDData does (DM2USBMIDI.cpp:72), with a timeout where allowed.
	printf("  Driver-path LED write: pipe index 2, blink 4 times; WATCH THE DM2\n");
	for (int i = 0; i < 4; i++) {
		UInt8 v = (i % 2) ? 0xFF : 0x00;
		UInt8 buf[4] = {v, v, 0xFF, 0xFF};
		UInt8 dir = 0, num = 0, type = 0, interval = 0;
		UInt16 maxPacket = 0;
		IOReturn pr = (*intf)->GetPipeProperties(intf, 2, &dir, &num, &type, &maxPacket, &interval);
		if (pr == kIOReturnSuccess && type == kUSBBulk)
			r = (*intf)->WritePipeTO(intf, 2, buf, 4, 1000, 1000);
		else
			r = (*intf)->WritePipe(intf, 2, buf, 4); // unknown pipe fails immediately
		char what[48];
		snprintf(what, sizeof what, "write %d (%02x %02x ff ff)", i, v, v);
		printRet(what, r);
		if (r != kIOReturnSuccess)
			break;
		usleep(250000);
	}

	(*intf)->USBInterfaceClose(intf);
	(*intf)->Release(intf);
}
