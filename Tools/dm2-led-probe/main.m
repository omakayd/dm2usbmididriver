// dm2-led-probe: find out exactly what macOS does with the DM2's LED endpoint.
//
// The DM2 (VID 0x0665 PID 0x0301) is a low-speed device whose LED endpoint 0x02 is
// declared Bulk OUT, which the USB spec forbids at low speed. This tool reports:
//   1. the descriptors macOS sees and the device speed
//   2. whether IOUSBHost will create a pipe for 0x02 (and 0x81), and with what type
//   3. an LED blink attempt on 0x02 if a pipe exists
//   4. a short read on 0x81 to prove the probe path itself works
//   5. the legacy IOUSBLib pipe table the driver actually uses (WritePipe index 2)
//
// Usage: dm2-led-probe [--capture] [--no-legacy] [--override] [--catalog-add | --catalog-remove]
//   --capture         take the device from any other client (needs sudo). Use this if the
//                     DM2 driver is installed and MIDIServer holds the interface.
//   --override        set kUSBDescriptorOverride (fixed config descriptor, 0x02 as Interrupt)
//                     directly on the live device, then capture + reconfigure and run the tests.
//   --catalog-add     add a no-code AppleUSBHostMergeProperties personality carrying the same
//                     override to the running kernel's driver catalogue, then reset the DM2 so it
//                     re-enumerates with it. Lasts until reboot or --catalog-remove.
//   --catalog-remove  remove that personality again and reset the DM2.

#import <Foundation/Foundation.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOKitServer.h>
#import <IOUSBHost/IOUSBHost.h>
#include <mach/mach_error.h>
#include <libkern/OSByteOrder.h>
#include "legacy.h"

static const uint16_t kVID = 0x0665, kPID = 0x0301;

static void printErr(const char *what, NSError *err)
{
	IOReturn code = (IOReturn)err.code;
	printf("  %s FAILED: 0x%08x (%s)\n", what, code, mach_error_string(code));
}

static const char *xferTypeName(uint8_t bmAttributes)
{
	switch (bmAttributes & 0x03) {
		case 0: return "Control";
		case 1: return "Isochronous";
		case 2: return "Bulk";
		default: return "Interrupt";
	}
}

static void printEndpoint(const char *prefix, const IOUSBEndpointDescriptor *ep)
{
	printf("%saddr=0x%02x %s %s maxPacket=%u interval=%u (bmAttributes=0x%02x)\n", prefix,
		   ep->bEndpointAddress, (ep->bEndpointAddress & 0x80) ? "IN " : "OUT",
		   xferTypeName(ep->bmAttributes), OSSwapLittleToHostInt16(ep->wMaxPacketSize), ep->bInterval,
		   ep->bmAttributes);
}

static void printChildren(const char *label, io_registry_entry_t entry)
{
	io_iterator_t it = 0;
	if (IORegistryEntryGetChildIterator(entry, kIOServicePlane, &it) != KERN_SUCCESS)
		return;
	printf("  %s children:", label);
	io_object_t child;
	int n = 0;
	while ((child = IOIteratorNext(it))) {
		io_name_t cls;
		IOObjectGetClass(child, cls);
		printf(" %s", cls);
		IOObjectRelease(child);
		n++;
	}
	printf(n ? "\n" : " (none)\n");
	IOObjectRelease(it);
}

static void printInterestingProperties(io_registry_entry_t entry)
{
	CFMutableDictionaryRef props = NULL;
	if (IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) != KERN_SUCCESS || !props)
		return;
	NSDictionary *d = CFBridgingRelease(props);
	for (NSString *key in [d.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		NSString *lk = key.lowercaseString;
		if ([lk containsString:@"speed"] || [lk containsString:@"location"] || [lk containsString:@"port"])
			printf("  %s = %s\n", key.UTF8String, [[d[key] description] UTF8String]);
	}
}

static io_service_t findService(CFMutableDictionaryRef matching)
{
	// IOServiceGetMatchingService consumes the dictionary.
	return IOServiceGetMatchingService(MACH_PORT_NULL, matching); // MACH_PORT_NULL = default main port, 11.0-safe
}

static io_service_t findInterfaceChild(io_service_t device, int interfaceNumber)
{
	io_iterator_t it = 0;
	if (IORegistryEntryGetChildIterator(device, kIOServicePlane, &it) != KERN_SUCCESS)
		return 0;
	io_service_t found = 0, child;
	while (!found && (child = IOIteratorNext(it))) {
		if (IOObjectConformsTo(child, "IOUSBHostInterface")) {
			CFTypeRef num = IORegistryEntryCreateCFProperty(child, CFSTR("bInterfaceNumber"), kCFAllocatorDefault, 0);
			int n = -1;
			if (num && CFGetTypeID(num) == CFNumberGetTypeID())
				CFNumberGetValue((CFNumberRef)num, kCFNumberIntType, &n);
			if (num) CFRelease(num);
			if (n == interfaceNumber) {
				found = child;
				continue;
			}
		}
		IOObjectRelease(child);
	}
	IOObjectRelease(it);
	return found;
}

static void dumpDescriptors(IOUSBHostInterface *obj)
{
	const IOUSBDeviceDescriptor *dd = obj.deviceDescriptor;
	if (dd)
		printf("  Device: bcdUSB=0x%04x class=%u maxPacket0=%u VID=0x%04x PID=0x%04x bcdDevice=0x%04x\n",
			   OSSwapLittleToHostInt16(dd->bcdUSB), dd->bDeviceClass, dd->bMaxPacketSize0,
			   OSSwapLittleToHostInt16(dd->idVendor), OSSwapLittleToHostInt16(dd->idProduct), OSSwapLittleToHostInt16(dd->bcdDevice));

	const IOUSBConfigurationDescriptor *cd = obj.configurationDescriptor;
	if (!cd) {
		printf("  (no configuration descriptor)\n");
		return;
	}
	uint16_t total = OSSwapLittleToHostInt16(cd->wTotalLength);
	printf("  Config raw (%u bytes):", total);
	for (uint16_t i = 0; i < total; i++)
		printf(" %02x", ((const uint8_t *)cd)[i]);
	printf("\n");

	const IOUSBInterfaceDescriptor *ifd = NULL;
	while ((ifd = IOUSBGetNextInterfaceDescriptor(cd, (const IOUSBDescriptorHeader *)ifd))) {
		printf("  Interface %u alt %u: %u endpoints\n", ifd->bInterfaceNumber, ifd->bAlternateSetting, ifd->bNumEndpoints);
		const IOUSBEndpointDescriptor *ep = NULL;
		while ((ep = IOUSBGetNextEndpointDescriptor(cd, ifd, (const IOUSBDescriptorHeader *)ep)))
			printEndpoint("    descriptor: ", ep);
	}
}

static IOUSBHostPipe *tryPipe(IOUSBHostInterface *intf, uint8_t addr)
{
	NSError *err = nil;
	IOUSBHostPipe *pipe = [intf copyPipeWithAddress:addr error:&err];
	if (!pipe) {
		char what[64];
		snprintf(what, sizeof what, "copyPipeWithAddress(0x%02x)", addr);
		printErr(what, err);
		return nil;
	}
	printf("  copyPipeWithAddress(0x%02x) OK\n", addr);
	const IOUSBHostIOSourceDescriptors *d = pipe.descriptors;
	if (d)
		printEndpoint("    pipe as created by macOS: ", &d->descriptor);
	return pipe;
}

static void blinkTest(IOUSBHostPipe *pipe)
{
	// LED packet format, from DM2USBMIDI.cpp:250-266: bytes 0-1 are the 16 LED bits
	// (driver alternates 0x0000 / 0xFFFF on startup), bytes 2-3 are 0xFFFF.
	const IOUSBHostIOSourceDescriptors *d = pipe.descriptors;
	BOOL isInterrupt = d && (d->descriptor.bmAttributes & 0x03) == 3;
	NSTimeInterval timeout = isInterrupt ? 0 : 1.0; // interrupt pipes require 0
	printf("  Blinking LEDs 6 times; WATCH THE DM2 (timeout %.1fs)\n", timeout);
	for (int i = 0; i < 6; i++) {
		uint8_t v = (i % 2) ? 0xFF : 0x00;
		uint8_t bytes[4] = {v, v, 0xFF, 0xFF};
		NSMutableData *data = [NSMutableData dataWithBytes:bytes length:4];
		NSUInteger done = 0;
		NSError *err = nil;
		if ([pipe sendIORequestWithData:data bytesTransferred:&done completionTimeout:timeout error:&err]) {
			printf("    write %d (%02x %02x ff ff): OK, %lu bytes\n", i, v, v, (unsigned long)done);
		} else {
			printErr("    write", err);
			if (err.code == kUSBHostReturnPipeStalled) {
				NSError *e2 = nil;
				if (![pipe clearStallWithError:&e2]) printErr("    clearStall", e2);
			}
			break;
		}
		usleep(250000);
	}
	// Same "clear" packet the driver sends in StopInterface.
	uint8_t clear[4] = {0xFF, 0xFF, 0x00, 0x00};
	[pipe sendIORequestWithData:[NSMutableData dataWithBytes:clear length:4]
			   bytesTransferred:NULL completionTimeout:timeout error:NULL];
}

static void readTest(IOUSBHostPipe *pipe)
{
	printf("  Reading 0x81 for up to 3s; press or move any DM2 control now...\n");
	NSMutableData *buf = [NSMutableData dataWithLength:8];
	dispatch_semaphore_t sem = dispatch_semaphore_create(0);
	__block IOReturn status = kIOReturnTimeout;
	__block NSUInteger got = 0;
	NSError *err = nil;
	BOOL queued = [pipe enqueueIORequestWithData:buf completionTimeout:0 error:&err
							   completionHandler:^(IOReturn s, NSUInteger n) {
		status = s;
		got = n;
		dispatch_semaphore_signal(sem);
	}];
	if (!queued) {
		printErr("enqueue read", err);
		return;
	}
	if (dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) != 0) {
		[pipe abortWithOption:IOUSBHostAbortOptionSynchronous error:NULL];
		dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC));
		printf("    no input within 3s (not necessarily an error)\n");
		return;
	}
	if (status != kIOReturnSuccess) {
		printf("    read FAILED: 0x%08x (%s)\n", status, mach_error_string(status));
		return;
	}
	printf("    read OK, %lu bytes:", (unsigned long)got);
	for (NSUInteger i = 0; i < got; i++)
		printf(" %02x", ((uint8_t *)buf.mutableBytes)[i]);
	printf("\n");
}

// The DM2's configuration descriptor with endpoint 0x02 changed from Bulk (02, interval 0)
// to Interrupt (03, interval 10 ms): the same fix Linux applies to low-speed bulk endpoints.
static const uint8_t kFixedConfig[32] = {
	0x09, 0x02, 0x20, 0x00, 0x01, 0x01, 0x00, 0x80, 0x00,
	0x09, 0x04, 0x00, 0x00, 0x02, 0xFF, 0xFF, 0xFF, 0x00,
	0x07, 0x05, 0x81, 0x03, 0x08, 0x00, 0x0A,
	0x07, 0x05, 0x02, 0x03, 0x08, 0x00, 0x0A,
};

// Same shape Apple uses in AppleUSBHostMergeProperties.kext (e.g. "Built-in iSight3").
static NSDictionary *overrideValue(void)
{
	return @{ @"descriptor": [NSData dataWithBytes:kFixedConfig length:sizeof kFixedConfig],
			  @"index": @0,
			  @"languageID": @0 };
}

static NSDictionary *mergePersonality(void)
{
	return @{ @"CFBundleIdentifier": @"com.apple.driver.AppleUSBHostMergeProperties",
			  @"IOClass": @"AppleUSBHostMergeProperties",
			  @"IOProviderClass": @"IOUSBHostDevice",
			  @"idVendor": @(kVID),
			  @"idProduct": @(kPID),
			  @"IOProviderMergeProperties": @{ @"kUSBDescriptorOverride": overrideValue() } };
}

static IOReturn catalogueSend(uint32_t flag, id plist)
{
	NSError *err = nil;
	NSData *xml = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0
															options:0 error:&err];
	if (!xml) return kIOReturnBadArgument;
	NSMutableData *buf = [xml mutableCopy];
	[buf appendBytes:"" length:1]; // the kernel's XML parser wants a NUL-terminated buffer
	return IOCatalogueSendData(MACH_PORT_NULL, flag, buf.bytes, (uint32_t)buf.length);
}

static void resetDevice(io_service_t devService)
{
	// Capturing and then destroying resets the device; it re-enumerates and drivers rematch.
	NSError *err = nil;
	IOUSBHostDevice *dev = [[IOUSBHostDevice alloc] initWithIOService:devService
															  options:IOUSBHostObjectInitOptionsDeviceCapture
																queue:nil error:&err interestHandler:nil];
	if (!dev) {
		printErr("reset (capture)", err);
		printf("  Unplug and replug the DM2 instead.\n");
		return;
	}
	[dev destroy];
	printf("  DM2 reset; it will re-enumerate in a second or two.\n");
}

int main(int argc, const char *argv[])
{
	@autoreleasepool {
		BOOL capture = NO, legacy = YES, override = NO, catAdd = NO, catRemove = NO;
		for (int i = 1; i < argc; i++) {
			if (!strcmp(argv[i], "--capture")) capture = YES;
			else if (!strcmp(argv[i], "--no-legacy")) legacy = NO;
			else if (!strcmp(argv[i], "--override")) override = capture = YES;
			else if (!strcmp(argv[i], "--catalog-add")) catAdd = YES;
			else if (!strcmp(argv[i], "--catalog-remove")) catRemove = YES;
			else {
				fprintf(stderr, "usage: %s [--capture] [--no-legacy] [--override] [--catalog-add | --catalog-remove]\n", argv[0]);
				return 2;
			}
		}

		NSProcessInfo *pi = NSProcessInfo.processInfo;
		printf("dm2-led-probe  %s  macOS %s  uid=%d\n",
			   [[NSDate.date description] UTF8String], pi.operatingSystemVersionString.UTF8String, getuid());

		// --- 1. Device ---------------------------------------------------------------
		printf("\n[1] Device\n");
		io_service_t devService = findService([IOUSBHostDevice createMatchingDictionaryWithVendorID:@(kVID)
																						 productID:@(kPID)
																						 bcdDevice:nil
																					   deviceClass:nil
																					deviceSubclass:nil
																					deviceProtocol:nil
																							 speed:nil
																					productIDArray:nil]);
		if (!devService) {
			printf("  DM2 not found. Plug it in (directly, not through a hub, for the first run).\n");
			return 1;
		}
		printInterestingProperties(devService);
		printChildren("device", devService);
		{
			CFTypeRef existing = IORegistryEntryCreateCFProperty(devService, CFSTR("kUSBDescriptorOverride"), kCFAllocatorDefault, 0);
			printf("  kUSBDescriptorOverride on device: %s\n", existing ? "PRESENT" : "absent");
			if (existing) CFRelease(existing);
		}

		if (catAdd || catRemove) {
			printf("\n[catalog] %s personality\n", catAdd ? "Adding" : "Removing");
			IOReturn r = catAdd
				? catalogueSend(kIOCatalogAddDrivers, @[ mergePersonality() ])
				: catalogueSend(kIOCatalogRemoveDrivers, @{ @"IOClass": @"AppleUSBHostMergeProperties",
															 @"idVendor": @(kVID), @"idProduct": @(kPID) });
			printf("  IOCatalogueSendData: 0x%08x (%s)\n", r, r ? mach_error_string(r) : "success");
			// Measured on macOS 26.5.2: the kernel logs "IOCatalogueSendData(...): Not entitled" and ignores the
			// request (root or not), yet IOKitLib still returns 0. The return code cannot be trusted.
			printf("  NOTE: 0 does not mean accepted. The kernel requires a private Apple entitlement and\n"
				   "  logs \"Not entitled\" when it drops the request (see the kernel log section).\n");
			if (r == kIOReturnSuccess)
				resetDevice(devService);
			IOObjectRelease(devService);
			if (r != kIOReturnSuccess)
				return 1;

			// Wait for the DM2 to come back, then see whether the override was merged onto it.
			printf("  Waiting up to 10s for the DM2 to re-enumerate...\n");
			usleep(1500000);
			io_service_t again = 0;
			for (int tries = 0; tries < 85 && !again; tries++) {
				again = findService([IOUSBHostDevice createMatchingDictionaryWithVendorID:@(kVID) productID:@(kPID)
																				bcdDevice:nil deviceClass:nil deviceSubclass:nil
																		   deviceProtocol:nil speed:nil productIDArray:nil]);
				if (!again) usleep(100000);
			}
			if (!again) {
				printf("  DM2 did not come back within 10s.\n");
				return 1;
			}
			usleep(1000000); // give matching a moment to run
			uint64_t regID = 0;
			IORegistryEntryGetRegistryEntryID(again, &regID);
			CFTypeRef merged = IORegistryEntryCreateCFProperty(again, CFSTR("kUSBDescriptorOverride"), kCFAllocatorDefault, 0);
			printf("  DM2 back (registry id 0x%llx); kUSBDescriptorOverride: %s\n", regID, merged ? "PRESENT" : "absent");
			if (merged) CFRelease(merged);
			printChildren("device", again);
			IOObjectRelease(again);
			printf("\nIf PRESENT: watch for the driver's LED flash, then run `sudo ./run_probe.sh --capture`.\n");
			return 0;
		}

		if (override) {
			printf("\n[override] Setting kUSBDescriptorOverride on the live device\n");
			kern_return_t r = IORegistryEntrySetCFProperty(devService, CFSTR("kUSBDescriptorOverride"),
														   (__bridge CFTypeRef)overrideValue());
			printf("  IORegistryEntrySetCFProperty: 0x%08x (%s)\n", r, r ? mach_error_string(r) : "success");
			CFTypeRef readBack = IORegistryEntryCreateCFProperty(devService, CFSTR("kUSBDescriptorOverride"), kCFAllocatorDefault, 0);
			printf("  read back: %s\n", readBack ? "PRESENT" : "absent");
			if (readBack) CFRelease(readBack);
		}

		IOUSBHostDevice *device = nil;
		if (capture) {
			NSError *err = nil;
			device = [[IOUSBHostDevice alloc] initWithIOService:devService
														options:IOUSBHostObjectInitOptionsDeviceCapture
														  queue:nil error:&err interestHandler:nil];
			if (!device) {
				printErr("device capture (are you running with sudo?)", err);
				return 1;
			}
			printf("  device captured\n");
			// matchInterfaces:NO keeps MIDIServer's driver from grabbing the new interface first.
			if (![device configureWithValue:1 matchInterfaces:NO error:&err])
				printErr("configureWithValue(1)", err);
		}

		// --- 2. Interface + descriptors -------------------------------------------------
		printf("\n[2] Interface 0 and descriptors\n");
		// Look for the interface as a child of the device rather than by matching, because an
		// interface that was not registered for matching is invisible to IOServiceGetMatching*.
		io_service_t intfService = 0;
		for (int tries = 0; tries < 50 && !intfService; tries++) {
			intfService = findInterfaceChild(devService, 0);
			if (!intfService) usleep(100000);
		}
		if (!intfService) {
			printf("  interface 0 not found under the device after 5s\n");
			printChildren("device (after configure)", devService);
			IOObjectRelease(devService);
			[device destroy];
			return 1;
		}
		IOObjectRelease(devService);
		printChildren("interface", intfService);

		NSError *err = nil;
		IOUSBHostInterface *intf = [[IOUSBHostInterface alloc] initWithIOService:intfService
																		 options:IOUSBHostObjectInitOptionsNone
																		   queue:nil error:&err interestHandler:nil];
		if (!intf) {
			printErr("open interface", err);
			printf("  If this is kIOReturnExclusiveAccess, the DM2 driver/MIDIServer holds it:\n"
				   "  rerun with sudo and --capture, or remove the driver and `sudo killall MIDIServer`.\n");
		} else {
			dumpDescriptors(intf);

			// --- 3. Pipes --------------------------------------------------------------
			printf("\n[3] Pipe creation (IOUSBHost)\n");
			IOUSBHostPipe *inPipe = tryPipe(intf, 0x81);
			IOUSBHostPipe *ledPipe = tryPipe(intf, 0x02);

			if (!ledPipe) {
				printf("  Retrying 0x02 after selectAlternateSetting(0)...\n");
				if (![intf selectAlternateSetting:0 error:&err])
					printErr("selectAlternateSetting(0)", err);
				else
					ledPipe = tryPipe(intf, 0x02);
			}

			// --- 4. I/O ----------------------------------------------------------------
			printf("\n[4] LED write on 0x02\n");
			if (ledPipe) blinkTest(ledPipe);
			else printf("  skipped: no pipe for 0x02\n");

			printf("\n[5] Input read on 0x81 (sanity check of the probe path)\n");
			if (inPipe) readTest(inPipe);
			else printf("  skipped: no pipe for 0x81\n");

			[intf destroy];
			intf = nil;
		}

		// --- 5. Legacy IOUSBLib view (what the driver uses) --------------------------------
		if (legacy) {
			printf("\n[6] Legacy IOUSBLib pipe table (driver path: WritePipe index 2)\n");
			legacyProbe(intfService);
		}
		IOObjectRelease(intfService);

		if (device) [device destroy]; // resets the device and lets drivers rematch
		printf("\nDone.\n");
	}
	return 0;
}
