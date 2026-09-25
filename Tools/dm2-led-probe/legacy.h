#pragma once
#include <IOKit/IOKitLib.h>

#ifdef __cplusplus
extern "C" {
#endif

// Opens the interface through IOUSBLib (the API the DM2 driver uses), prints its pipe
// table, and tries the driver's exact LED write: WritePipe(pipe index 2, 4 bytes).
void legacyProbe(io_service_t interfaceService);

#ifdef __cplusplus
}
#endif
