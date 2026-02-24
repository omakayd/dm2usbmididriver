// CAHostTimeBase.h — Minimal replacement for Apple's CoreAudio PublicUtility class.
// Provides only the API surface used by this project.

#ifndef __CAHostTimeBase_h__
#define __CAHostTimeBase_h__

#include <mach/mach_time.h>
#include <CoreFoundation/CoreFoundation.h>

class CAHostTimeBase {
public:
	static UInt64 GetCurrentTime()
	{
		return mach_absolute_time();
	}

	static UInt64 ConvertToNanos(UInt64 inHostTime)
	{
		struct mach_timebase_info info;
		mach_timebase_info(&info);
		return inHostTime * info.numer / info.denom;
	}

	static UInt64 ConvertFromNanos(UInt64 inNanos)
	{
		struct mach_timebase_info info;
		mach_timebase_info(&info);
		return inNanos * info.denom / info.numer;
	}
};

#endif // __CAHostTimeBase_h__
