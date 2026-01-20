//
//  ARM64RecompilerIOS.h
//  ARMSX2
//
//  iOS-specific ARM64 recompiler integration
//

#pragma once

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// ARM64 code block management (used by PCSX2)
void* armAllocateCodeBlock(size_t size);
void armFreeCodeBlock(void* ptr);
void* armGetWritableCodePointer(const void* code_ptr);
void armFinalizeCodeBlock(const void* code_ptr, size_t size);

#ifdef __cplusplus
}
#endif

#ifdef __cplusplus

namespace ARM64RecompilerIOS
{
    // Initialize recompiler
    bool Initialize();

    // Shutdown recompiler
    void Shutdown();

    // Forward declaration
    class CodeBlock;
}

#endif
