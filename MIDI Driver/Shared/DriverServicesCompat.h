// DriverServicesCompat.h — Replacement for Carbon DriverServices.h
// Provides UpTime() and AbsoluteDeltaToDuration() using mach_absolute_time.
// AbsoluteTime is UnsignedWide (from MacTypes.h via CoreMIDI).

#ifndef __DriverServicesCompat_h__
#define __DriverServicesCompat_h__

#include <mach/mach_time.h>
#include <stdint.h>
#include <MacTypes.h>

// Duration: positive = milliseconds, negative = microseconds
#ifndef __DRIVERSERVICES__
typedef SInt32 Duration;
#endif

// Helper: convert UnsignedWide to/from uint64_t
static inline uint64_t _AbsoluteTimeToU64(AbsoluteTime t)
{
	return ((uint64_t)t.hi << 32) | t.lo;
}

static inline AbsoluteTime _U64ToAbsoluteTime(uint64_t v)
{
	AbsoluteTime t;
	t.hi = (UInt32)(v >> 32);
	t.lo = (UInt32)(v & 0xFFFFFFFF);
	return t;
}

static inline AbsoluteTime UpTime(void)
{
	return _U64ToAbsoluteTime(mach_absolute_time());
}

// Returns duration between two AbsoluteTime values.
// Negative = microseconds (Carbon convention for sub-millisecond durations).
static inline Duration AbsoluteDeltaToDuration(AbsoluteTime end, AbsoluteTime start)
{
	uint64_t endVal = _AbsoluteTimeToU64(end);
	uint64_t startVal = _AbsoluteTimeToU64(start);
	uint64_t delta = (endVal > startVal) ? (endVal - startVal) : (startVal - endVal);

	struct mach_timebase_info info;
	mach_timebase_info(&info);
	uint64_t nanos = delta * info.numer / info.denom;

	int64_t micros = (int64_t)(nanos / 1000);
	if (micros > INT32_MAX)
		return INT32_MAX;
	return (Duration)(-micros);
}

#endif // __DriverServicesCompat_h__
