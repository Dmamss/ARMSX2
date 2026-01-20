//
//  RecMemoryIOS.mm
//  ARMSX2
//
//  iOS recompiler memory management implementation
//

#import "RecMemoryIOS.h"
#import "../JIT/JITManager_DolphinOS.h"
#import <Foundation/Foundation.h>

// C API Implementation
void RecMemory_iOS_Initialize(void)
{
    ARMSX2_JIT_Initialize();
}

void RecMemory_iOS_Shutdown(void)
{
    ARMSX2_JIT_Shutdown();
}

void* RecMemory_iOS_AllocateCode(size_t size)
{
    return ARMSX2_JIT_Allocate(size);
}

void RecMemory_iOS_FreeCode(void* ptr)
{
    ARMSX2_JIT_Free(ptr);
}

void* RecMemory_iOS_GetWritablePointer(const void* code_ptr)
{
    return ARMSX2_JIT_GetWritablePointer(code_ptr);
}

void RecMemory_iOS_FlushCache(const void* code_ptr, size_t size)
{
    ARMSX2_JIT_FlushCache(code_ptr, size);
}

// C++ API Implementation
namespace RecMemoryIOS
{
    bool Initialize()
    {
        RecMemory_iOS_Initialize();
        return ARMSX2_JIT_IsInitialized() != 0;
    }

    void Shutdown()
    {
        RecMemory_iOS_Shutdown();
    }

    void* AllocateCode(size_t size)
    {
        return RecMemory_iOS_AllocateCode(size);
    }

    void FreeCode(void* ptr)
    {
        RecMemory_iOS_FreeCode(ptr);
    }

    void* GetWritablePointer(const void* code_ptr)
    {
        return RecMemory_iOS_GetWritablePointer(code_ptr);
    }

    void FlushCache(const void* code_ptr, size_t size)
    {
        RecMemory_iOS_FlushCache(code_ptr, size);
    }
}
