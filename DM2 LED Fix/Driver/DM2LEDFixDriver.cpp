//
//  DM2LEDFixDriver.cpp
//

#include <os/log.h>
#include <DriverKit/IOLib.h>
#include "DM2LEDFixDriver.h"

kern_return_t
IMPL(DM2LEDFixDriver, Start)
{
    kern_return_t ret = Start(provider, SUPERDISPATCH);
    os_log(OS_LOG_DEFAULT, "DM2LEDFix: Start 0x%08x", ret);
    return ret;
}
