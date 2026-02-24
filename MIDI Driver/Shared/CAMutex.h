// CAMutex.h — Minimal replacement for Apple's CoreAudio PublicUtility class.
// Provides only the API surface used by this project.

#ifndef __CAMutex_h__
#define __CAMutex_h__

#include <pthread.h>

class CAMutex {
public:
	CAMutex(const char *name = "unnamed")
	{
		pthread_mutexattr_t attr;
		pthread_mutexattr_init(&attr);
		pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
		pthread_mutex_init(&mMutex, &attr);
		pthread_mutexattr_destroy(&attr);
	}

	~CAMutex()
	{
		pthread_mutex_destroy(&mMutex);
	}

	void Lock()
	{
		pthread_mutex_lock(&mMutex);
	}

	void Unlock()
	{
		pthread_mutex_unlock(&mMutex);
	}

	// RAII locker — used as: CAMutex::Locker lock(mWriteQueueMutex);
	class Locker {
	public:
		Locker(CAMutex &mutex) : mMutex(mutex) { mMutex.Lock(); }
		~Locker() { mMutex.Unlock(); }
	private:
		CAMutex &mMutex;
	};

private:
	pthread_mutex_t mMutex;
};

#endif // __CAMutex_h__
