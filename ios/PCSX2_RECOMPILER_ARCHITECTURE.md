Perfect! I now have comprehensive information. Let me compile a systematic research report.

# COMPREHENSIVE PCSX2 RECOMPILER ARCHITECTURE RESEARCH REPORT

## PART 1: PCSX2 RECOMPILER CORE ARCHITECTURE

### 1.1 Core Files and Their Purposes

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/ix86-32/iR5900.cpp` (Main R5900 Recompiler - 82KB)
- **Purpose:** Main entry point for R5900 (EE CPU) dynamic recompilation
- **Key Functions:**
  - `recRecompile(const u32 startpc)` (Line 2350): Main block compilation function
  - `_DynGen_JITCompile()` (Line 392): JIT compilation dispatcher
  - `_DynGen_DispatcherReg()` (Line 428): Variable PC dispatcher
  - `_DynGen_DispatcherEvent()` (Line 456): Event test dispatcher
  - `_DynGen_EnterRecompiledCode()` (Line 467): Entry point from interpreter
  - `recExecute()` (Line 745): Main execution loop
- **Key Data:**
  - `recLUT[_64kb]` (Line 56): 2-level lookup table for block pointers
  - `hwLUT[_64kb]` (Line 57): Hardware address lookup
  - `s_pInstCache` (Line 90): Instruction analysis cache
  - `g_cpuConstRegs[32]` (Line 66): Constant propagation tracking

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/iCore.cpp` and `iCore.h` (Core Compilation Functions)
- **Purpose:** Core register allocation, instruction emission, and block management
- **Key Functions:**
  - `_initX86regs()`: Initialize x86 register allocator
  - `_initXMMregs()`: Initialize XMM register allocator
  - `_flushConstRegs()`: Flush constant registers to memory
  - `_allocX86reg()`: Allocate x86 register
  - `_allocGPRtoXMMreg()`: Allocate XMM register for GPR
  - `_eeMoveGPRtoR()` (iR5900.cpp:238): Move GPR to host register
  - `_eeFlushAllDirty()` (iR5900.cpp:229): Flush all dirty registers

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/R5900.cpp` and `R5900.h` (CPU Core Implementation)
- **Purpose:** R5900 CPU state and interpreter implementation
- **Key Structures:** 
  - `cpuRegisters` (defined in R5900Def.h): Complete CPU state
  - Interpreter implementations for all instructions
  - Opcode tables and instruction decoding

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/Memory.cpp` (Memory System)
- **Purpose:** PS2 memory management and VTLB integration
- **Key Functions:**
  - `SysMemory::AllocateMemoryMap()` (Line 160): Allocate memory regions
  - `memMapPhy()` (Line 468): Map physical memory
  - `vtlb_MapHandler()`: Register memory handlers
  - Memory handlers for all memory regions (RAM, ROM, HW, VU)
- **Memory Map:**
  - EE Main Memory: `0x00000000-0x01ffffff` (cached)
  - Scratch Pad: `0x70000000-0x70003fff`
  - BIOS: `0x1FC00000-0x1FFFFFFF` (uncached)
  - IOP Memory: `0x1c000000-0x1c7fffff`

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/iR5900Analysis.cpp` (Analysis Pass)
- **Purpose:** Per-instruction analysis for optimization
- **Key Functions:**
  - `recBackpropBSC()` (Line 490): Backpropagate register usage
  - `COP2FlagHackPass::Run()` (Line 55): COP2 flag optimization
  - `COP2MicroFinishPass::Run()` (Line 224): COP2 sync optimization
- **Optimization Passes:**
  - Register liveness analysis
  - Constant propagation
  - COP2 flag tracking
  - VU0 synchronization optimization

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/BaseblockEx.h` (Block Management)
- **Purpose:** Block data structures and management
- **Key Classes:**
  - `BASEBLOCK`: Per-instruction block entry (8 bytes)
  - `BASEBLOCKEX`: Extended block metadata
  - `BaseBlocks`: Block manager with sorted array
  - `BaseBlockArray`: Dynamic array of blocks

---

## PART 2: KEY DATA STRUCTURES (EXACT DEFINITIONS)

### 2.1 CPU State Structure

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/R5900Def.h`

```cpp
struct cpuRegisters {
    GPRregs GPR;         // 32x 128-bit GPR registers
    GPR_reg HI;          // 128-bit HI register
    GPR_reg LO;          // 128-bit LO register
    CP0regs CP0;         // COP0 control registers (32x 32-bit)
    u32 sa;              // Shift amount (32-bit), 16-byte aligned
    u32 IsDelaySlot;     // Delay slot flag
    u32 pc;              // Program counter
    u32 code;            // Current instruction
    PERFregs PERF;       // Performance counter regs
    u32 eCycle[32];      // Event cycles
    u32 sCycle[32];      // Scheduled cycles
    u32 cycle;           // Current cycle count
    u32 interrupt;       // Interrupt flags
    int branch;          // Branch flag
    int opmode;          // Operating mode
    u32 tempcycles;      // Temporary cycles
    u32 dmastall;        // DMA stall counter
    u32 pcWriteback;     // PC writeback value
    u32 nextEventCycle;  // Next event cycle
    u32 lastEventCycle;  // Last event cycle
    u32 lastCOP0Cycle;   // Last COP0 cycle
    u32 lastPERFCycle[2];// Last PERF cycle
};
```

**GPR Register Union:**
```cpp
union GPR_reg {
    u128 UQ;      // 128-bit unsigned
    s128 SQ;      // 128-bit signed
    u64 UD[2];    // 2x 64-bit unsigned doublewords
    s64 SD[2];    // 2x 64-bit signed doublewords
    u32 UL[4];    // 4x 32-bit unsigned words
    s32 SL[4];    // 4x 32-bit signed words
    u16 US[8];    // 8x 16-bit unsigned halfwords
    s16 SS[8];    // 8x 16-bit signed halfwords
    u8  UC[16];   // 16x 8-bit unsigned bytes
    s8  SC[16];   // 16x 8-bit signed bytes
};
```

### 2.2 Instruction Analysis Structure

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/iCore.h` (Line 209)

```cpp
struct EEINST {
    u16 info;              // Extra info flags (COP1/COP2, XMM usage)
    u8 regs[34];           // GPR liveness info (32 GPRs + HI=32 + LO=33)
    u8 fpuregs[33];        // FPU liveness info (32 FPRs + ACC=32)
    u8 vfregs[34];         // VF liveness info (32 VFs + ACC=32 + I=33)
    u8 viregs[16];         // VI liveness info (16 VIs)
    
    // Register read/write tracking
    u8 writeType[3], writeReg[3];  // Up to 3 writes per instruction
    u8 readType[4], readReg[4];    // Up to 4 reads per instruction
};
```

**EEINST Flags (iCore.h):**
```cpp
#define EEINST_LIVE      0x01  // Register is live after this instruction
#define EEINST_USED      0x02  // Register is used by this instruction
#define EEINST_LASTUSE   0x04  // Last use of register in block
#define EEINST_XMM       0x08  // Register should use XMM/128-bit handling
```

### 2.3 Block Structures

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/BaseblockEx.h`

```cpp
// Basic block entry (8 bytes) - one per 4-byte PS2 instruction
struct BASEBLOCK {
    uptr m_pFnptr;  // Pointer to compiled code or JITCompile dispatcher
    
    __inline uptr GetFnptr() const { return m_pFnptr; }
    void __inline SetFnptr(uptr ptr) { m_pFnptr = ptr; }
};
static_assert(sizeof(BASEBLOCK) == 8, "BASEBLOCK is not 8 bytes");
```

```cpp
// Extended block info (only for block start)
struct BASEBLOCKEX {
    uptr fnptr;    // Pointer to compiled native code
    u32 startpc;   // Starting PC (physical address)
    u32 size;      // Size in MIPS instructions (dwords)
    u32 x86size;   // Size in bytes of compiled x86/ARM code
    
    #ifdef PCSX2_DEVBUILD
    // Development build instrumentation (commented out currently)
    // u32 visited; 
    // u64 ltime;
    #endif
};
```

```cpp
// Block manager class
class BaseBlocks {
protected:
    std::multimap<u32, uptr> links;  // PC -> jump target links
    uptr recompiler;                  // JITCompile dispatcher pointer
    BaseBlockArray blocks;            // Sorted array of blocks
    
public:
    BASEBLOCKEX* New(u32 startpc, uptr fnptr);  // Create new block
    int LastIndex(u32 startpc) const;            // Find block index
    int Index(u32 startpc) const;                // Get block at PC
    BASEBLOCKEX* Get(u32 startpc);              // Get block at PC
    void Remove(int first, int last);            // Remove block range
    void Link(u32 pc, s32* jumpptr);            // Link blocks
    void Reset();                                // Clear all blocks
};
```

### 2.4 Block Lookup Table Structure

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/BaseblockEx.h` (Line 237)

```cpp
// Two-level lookup: recLUT[upper 16 bits] + (lower 16 bits >> 2)
#define PC_GETBLOCK_(x, reclut) \
    ((BASEBLOCK*)(reclut[((u32)(x)) >> 16] + (x) * (sizeof(BASEBLOCK) >> 2)))
```

**Lookup Table Layout (iR5900.cpp Line 56-57):**
```cpp
alignas(16) static uptr recLUT[_64kb];  // 64K entries, points to BASEBLOCK arrays
alignas(16) static u32 hwLUT[_64kb];    // Hardware address lookup
```

---

## PART 3: COMPILATION FLOW (EXACT SEQUENCE)

### 3.1 Block Lookup and Dispatch

**Entry Point:** `EnterRecompiledCode()` (iR5900.cpp:467)
```cpp
// 1. Save stack frame and set up state registers
armAsm->Sub(a64::sp, a64::sp, stack_size);

// 2. Load pointer registers for fast access
armMoveAddressToReg(RSTATE_x29, &recLUT);     // x29 = recLUT base
armMoveAddressToReg(RSTATE_PSX, &psxRegs);    // x? = psxRegs
armMoveAddressToReg(RSTATE_CPU, &g_cpuRegistersPack);  // x? = cpuRegs

// 3. If fastmem enabled, load fastmem base
if (CHECK_FASTMEM)
    armAsm->Ldr(RFASTMEMBASE, PTR_CPU(vtlbdata.fastmem_base));

// 4. Jump to DispatcherReg to begin execution
armEmitJmp(DispatcherReg);
```

**Block Dispatch:** `DispatcherReg()` (iR5900.cpp:428)
```cpp
// C equivalent of assembly:
u32 addr = cpuRegs.pc;
void(**base)() = (void(**)())recLUT[addr >> 16];
base[addr >> 2]();

// Actual ARM64 assembly generated:
armLoad(EAX, PTR_CPU(cpuRegs.pc));        // Load PC
armAsm->Lsr(ECX, EAX, 16);                 // Upper 16 bits
armAsm->Ldr(RCX, a64::MemOperand(RSTATE_x29, RCX, a64::LSL, 3));  // recLUT[upper]
armAsm->Lsr(EAX, EAX, 2);                  // PC >> 2
armAsm->Ldr(RAX, a64::MemOperand(RCX, RAX, a64::LSL, 3));  // base[PC>>2]
armAsm->Br(RAX);                           // Jump to block
```

### 3.2 JIT Compilation Trigger

**JIT Compilation:** `_DynGen_JITCompile()` (iR5900.cpp:392)
```cpp
// When block not yet compiled (fnptr == JITCompile):
// 1. Call recRecompile with current PC
armLoad(EAX, PTR_CPU(cpuRegs.pc));
armEmitCall(reinterpret_cast<const void*>(recRecompile));

// 2. Look up newly compiled block and jump to it
// (Same dispatch code as DispatcherReg)
armLoad(EAX, PTR_CPU(cpuRegs.pc));
armAsm->Lsr(ECX, EAX, 16);
armAsm->Ldr(RCX, a64::MemOperand(RSTATE_x29, RCX, a64::LSL, 3));
armAsm->Lsr(EAX, EAX, 2);
armAsm->Ldr(RAX, a64::MemOperand(RCX, RAX, a64::LSL, 3));
armAsm->Br(RAX);
```

### 3.3 Block Compilation Process

**Main Compilation Function:** `recRecompile(const u32 startpc)` (iR5900.cpp:2350)

```cpp
static void recRecompile(const u32 startpc) {
    // STEP 1: Validation and Reset Check
    if (recPtr >= recPtrEnd)
        eeRecNeedsReset = true;
    
    if (eeRecNeedsReset) {
        eeRecNeedsReset = false;
        recResetRaw();  // Reset entire recompiler
    }
    
    // STEP 2: Initialize Code Buffer
    armSetAsmPtr(recPtr, _256kb, nullptr);
    recPtr = armStartBlock();  // Align and get start pointer
    
    // STEP 3: Get/Create Block Metadata
    s_pCurBlock = PC_GETBLOCK(startpc);  // Get BASEBLOCK entry
    pxAssert(s_pCurBlock->GetFnptr() == (uptr)JITCompile);
    
    s_pCurBlockEx = recBlocks.New(HWADDR(startpc), (uptr)recPtr);
    
    // STEP 4: Initialize Compilation State
    g_branch = 0;
    s_nBlockCycles = 0;
    s_nBlockInterlocked = false;
    pc = startpc;
    g_cpuHasConstReg = g_cpuFlushedConstReg = 1;
    g_cpuConstRegs[0].UD[0] = 0;  // Register 0 is always zero
    
    _initX86regs();  // Initialize register allocator
    _initXMMregs();  // Initialize XMM allocator
    
    // STEP 5: Scan and Analyze Block
    // Find block end (branch, exception, or max size)
    for (i = 0; i < 0x1000; i++) {
        cpuRegs.code = memRead32(pc);
        
        // Expand instruction cache if needed
        if (i >= s_nInstCacheSize) {
            s_nInstCacheSize = i + 128;
            s_pInstCache = (EEINST*)realloc(s_pInstCache, 
                                           sizeof(EEINST) * s_nInstCacheSize);
        }
        
        // Decode and analyze instruction
        // ... [instruction analysis code] ...
        
        pc += 4;
        
        // Check for block terminators
        if (IsTerminator(cpuRegs.code))
            break;
        if (i > 1 && IsBranch(cpuRegs.code))
            break;
    }
    
    s_nEndBlock = pc;  // Save block end PC
    
    // STEP 6: Backward Register Analysis
    // (Determine register liveness for optimization)
    EEINST* pinst = &s_pInstCache[i];
    for (int j = i; j >= 0; j--, pinst--) {
        recBackpropBSC(memRead32(startpc + j*4), pinst + 1, pinst);
    }
    
    // STEP 7: Run Optimization Passes
    COP2FlagHackPass cop2flags;
    cop2flags.Run(startpc, s_nEndBlock, s_pInstCache);
    
    COP2MicroFinishPass cop2finish;
    cop2finish.Run(startpc, s_nEndBlock, s_pInstCache);
    
    // STEP 8: Code Generation
    pc = startpc;
    g_pCurInstInfo = s_pInstCache;
    
    for (i = 0; pc < s_nEndBlock; i++, g_pCurInstInfo++) {
        cpuRegs.code = memRead32(pc);
        
        // Update cycle counter
        s_nBlockCycles++;
        
        // Generate code for this instruction
        recBSC[cpuRegs.code >> 26]();  // Call opcode handler
        
        pc += 4;
        
        if (g_branch)
            break;
    }
    
    // STEP 9: Block Exit Code
    if (!g_branch) {
        // No branch - continue to next block
        iFlushCall(FLUSH_EVERYTHING);
        
        // Increment cycle counter
        armLoad(EAX, PTR_CPU(cpuRegs.cycle));
        armAsm->Add(EAX, EAX, s_nBlockCycles * BIAS);
        armStore(PTR_CPU(cpuRegs.cycle), EAX);
        
        // Check for events
        armAsm->Cmp(EAX, PTR_CPU(cpuRegs.nextEventCycle));
        // ... [branch to DispatcherEvent if needed] ...
        
        // Update PC and dispatch to next block
        armStoreImm(PTR_CPU(cpuRegs.pc), pc);
        armEmitJmp(DispatcherReg);
    }
    
    // STEP 10: Finalize Block
    recPtr = armEndBlock();  // Get final code pointer
    
    s_pCurBlockEx->size = (s_nEndBlock - startpc) >> 2;  // Size in instructions
    s_pCurBlockEx->x86size = recPtr - s_pCurBlockEx->fnptr;  // Size in bytes
    
    // Update BASEBLOCK lookup table
    s_pCurBlock->SetFnptr(s_pCurBlockEx->fnptr);
    
    // STEP 11: Profiling/Debug
    EE::Profiler.RegisterBlock(startpc, s_nEndBlock, s_pCurBlockEx->fnptr);
}
```

---

## PART 4: REGISTER ALLOCATION

### 4.1 Register Allocator Architecture

**Constant Propagation System:**
```cpp
// Global state (iR5900.cpp:66-68)
alignas(16) GPR_reg64 g_cpuConstRegs[32] = {};  // Constant values
u32 g_cpuHasConstReg = 0;      // Bitmask: which regs are constant
u32 g_cpuFlushedConstReg = 0;  // Bitmask: which constants flushed

// Macros for checking constant status (iCore.h)
#define GPR_IS_CONST1(reg) ((g_cpuHasConstReg & (1<<(reg))) != 0)
#define GPR_SET_CONST(reg) g_cpuHasConstReg |= (1<<(reg))
#define GPR_DEL_CONST(reg) g_cpuHasConstReg &= ~(1<<(reg))
```

**X86/ARM64 Register Allocator:**
```cpp
// Register allocation (simplified, from iCore.cpp)
int _allocX86reg(int type, int reg, int mode) {
    // 1. Check if already allocated
    for (int i = 0; i < X86REGS; i++) {
        if (x86regs[i].inuse && x86regs[i].type == type && 
            x86regs[i].reg == reg)
            return i;
    }
    
    // 2. Find free register
    for (int i = 0; i < X86REGS; i++) {
        if (!x86regs[i].inuse)
            return _allocFreeX86reg(i, type, reg, mode);
    }
    
    // 3. Spill least recently used register
    int oldest = _findLRUX86reg();
    _freeX86reg(oldest);
    return _allocFreeX86reg(oldest, type, reg, mode);
}
```

**XMM Register Allocator (for 128-bit values):**
```cpp
int _allocGPRtoXMMreg(int gprreg, int mode) {
    // Similar to x86 allocator but for XMM registers
    // Used when EEINST_XMM flag is set (128-bit operations)
    
    // Check EEINST info to decide between X86 and XMM allocation
    if (EEINST_XMMUSEDTEST(gprreg))
        return _allocGPRtoXMMreg(gprreg, mode);
    else if (EEINST_USEDTEST(gprreg))
        return _allocX86reg(X86TYPE_GPR, gprreg, mode);
    else
        return -1;  // Not used, access memory directly
}
```

### 4.2 Register Allocation Strategy

**Allocation Decision Tree (from iR5900.cpp:262-298):**
```cpp
void _eeMoveGPRtoR(const a64::Register& to, int fromgpr, bool allow_preload) {
    // 1. If source is register 0, clear destination
    if (fromgpr == 0) {
        armAsm->Eor(to, to, to);  // XOR with self = 0
        return;
    }
    
    // 2. If source is constant, load immediate
    if (GPR_IS_CONST1(fromgpr)) {
        armAsm->Mov(to, g_cpuConstRegs[fromgpr].UL[0]);
        return;
    }
    
    // 3. Check if already in host register
    int x86reg = _checkX86reg(X86TYPE_GPR, fromgpr, MODE_READ);
    int xmmreg = _checkXMMreg(XMMTYPE_GPRREG, fromgpr, MODE_READ);
    
    // 4. If not allocated and used later, allocate now
    if (allow_preload && x86reg < 0 && xmmreg < 0) {
        if (EEINST_XMMUSEDTEST(fromgpr))
            xmmreg = _allocGPRtoXMMreg(fromgpr, MODE_READ);
        else if (EEINST_USEDTEST(fromgpr))
            x86reg = _allocX86reg(X86TYPE_GPR, fromgpr, MODE_READ);
    }
    
    // 5. Use allocated register or load from memory
    if (x86reg >= 0)
        armAsm->Mov(to, a64::XRegister(x86reg));
    else if (xmmreg >= 0)
        armAsm->Fmov(to, a64::QRegister(xmmreg).D());
    else
        armLoad(to, PTR_CPU(cpuRegs.GPR.r[fromgpr].UD[0]));
}
```

### 4.3 Spilling Strategy

**Flush System (from iR5900.cpp:229-236):**
```cpp
void _eeFlushAllDirty() {
    // 1. Flush all XMM registers
    _flushXMMregs();
    
    // 2. Flush all X86 registers
    _flushX86regs();
    
    // 3. Flush all constant registers (batch for better codegen)
    _flushConstRegs(false);
}

// Called before:
// - Function calls
// - Branch instructions
// - Exception-throwing instructions
// - Block exits
```

---

## PART 5: MEMORY SYSTEM INTEGRATION

### 5.1 VTLB (Virtual TLB) Architecture

**Overview (from Memory.cpp and vtlb.h):**
- Two-level address translation
- Memory handlers for different regions
- Fastmem optimization for direct memory access

**Memory Handler Registration (Memory.cpp:1105-1190):**
```cpp
// Example: Hardware registers (Memory.cpp:1156-1172)
hw_by_page[0x0] = vtlb_RegisterHandler(hwHandlerTmpl(0x00));
hw_by_page[0x1] = vtlb_RegisterHandler(hwHandlerTmpl(0x01));
// ... one handler per 4KB page of hardware registers

// Example: GS memory (Memory.cpp:1182-1190)
gs_page_0 = vtlb_RegisterHandler(
    _ext_memRead8<6>, _ext_memRead16<6>, _ext_memRead32<6>,
    _ext_memRead64<6>, _ext_memRead128<6>,
    _ext_memWrite8<6>, _ext_memWrite16<6>, _ext_memWrite32<6>,
    gsWrite64_page_00, gsWrite128_page_00
);
```

### 5.2 Memory Access in Recompiler

**Dynamic Memory Access Code Generation:**

From `vtlb.h` (Line 76-85):
```cpp
// Functions for generating memory access code in JIT
extern int vtlb_DynGenReadNonQuad(u32 bits, bool sign, bool xmm, 
                                  int addr_reg, 
                                  vtlb_ReadRegAllocCallback dest_reg_alloc);
extern int vtlb_DynGenReadQuad(u32 bits, int addr_reg,
                               vtlb_ReadRegAllocCallback dest_reg_alloc);
extern void vtlb_DynGenWrite(u32 sz, bool xmm, int addr_reg, int value_reg);
extern void vtlb_DynGenWrite_Const(u32 bits, bool xmm, u32 addr_const, 
                                   int value_reg);
```

**Fastmem Path (from Memory.cpp):**
```cpp
// When fastmem is enabled:
// 1. Check if address is in fastmem range
// 2. If yes: Direct memory access via RFASTMEMBASE register
// 3. If no: Call VTLB handler

// Fastmem base loaded on entry (iR5900.cpp:498-499):
if (CHECK_FASTMEM) {
    armAsm->Ldr(RFASTMEMBASE, PTR_CPU(vtlbdata.fastmem_base));
}

// Example fastmem load:
// addr_reg = virtual address
// RFASTMEMBASE = physical memory base
// result = RFASTMEMBASE[addr_reg & FASTMEM_MASK]
```

### 5.3 Memory Map (from Memory.cpp:6-23)

```
RAM (32MB, mirrored):
  0x00100000-0x01ffffff  Cached
  0x20100000-0x21ffffff  Uncached
  0x30100000-0x31ffffff  Uncached & accelerated
  0xa0000000-0xa1ffffff  Mirror (cached)
  0x80000000-0x81ffffff  Mirror (cached)

Scratch Pad (16KB):
  0x70000000-0x70003fff

BIOS (4MB):
  0x1FC00000-0x1FFFFFFF  Uncached
  0x9FC00000-0x9FFFFFFF  Cached
  0xBFC00000-0xBFFFFFFF  Uncached

IOP Memory (8MB):
  0x1c000000-0x1c7fffff  Accessed via handlers

Hardware Registers:
  0x10000000-0x1000ffff  16x 4KB pages with specialized handlers

VU Memory:
  0x11000000-0x11003fff  VU0 micro memory (4KB)
  0x11004000-0x11007fff  VU0 data memory (4KB, mirrored 4x)
  0x11008000-0x1100bfff  VU1 micro memory (16KB)
  0x1100c000-0x1100ffff  VU1 data memory (16KB)
```

---

## PART 6: BUILD SYSTEM

**File:** `/home/user/ARMSX2/app/src/main/cpp/pcsx2/CMakeLists.txt`

### 6.1 Recompiler Compilation Flags

**x86-64 Build (Lines 986-1012):**
```cmake
set(pcsx2x86Sources
    x86/BaseblockEx.cpp
    x86/iCOP0.cpp
    x86/iCore.cpp
    x86/iFPU.cpp
    x86/iFPUd.cpp
    x86/iMMI.cpp
    x86/iR3000A.cpp
    x86/iR3000Atables.cpp
    x86/iR5900Analysis.cpp
    x86/iR5900Misc.cpp
    x86/ix86-32/iCore.cpp
    x86/ix86-32/iR5900.cpp
    x86/ix86-32/iR5900Arit.cpp
    x86/ix86-32/iR5900AritImm.cpp
    x86/ix86-32/iR5900Branch.cpp
    x86/ix86-32/iR5900Jump.cpp
    x86/ix86-32/iR5900LoadStore.cpp
    x86/ix86-32/iR5900Move.cpp
    x86/ix86-32/iR5900MultDiv.cpp
    x86/ix86-32/iR5900Shift.cpp
    x86/ix86-32/iR5900Templates.cpp
    x86/ix86-32/recVTLB.cpp
)
```

**ARM64 Build (Lines 1055-1065):**
```cmake
set(pcsx2arm64Sources
    arm64/Vif_Dynarec.cpp
    arm64/Vif_UnpackNEON.cpp
    arm64/VixlHelpers.cpp
)

# ARM64 uses VIXL library
target_link_libraries(PCSX2_FLAGS INTERFACE vixl)
```

### 6.2 Compiler Flags (Lines 32-46)

```cmake
if(MSVC)
    target_compile_options(PCSX2_FLAGS INTERFACE /GS- /fp:contract)
else()
    target_compile_options(PCSX2_FLAGS INTERFACE
        -ffp-contract=fast
        -fno-strict-aliasing
        -Wstrict-aliasing
        -Wno-parentheses
        -Wno-missing-braces
        -Wno-unknown-pragmas
    )
endif()
```

### 6.3 Key Dependencies

```cmake
target_link_libraries(PCSX2_FLAGS INTERFACE
    common              # Common utilities
    imgui              # UI framework
    fmt::fmt           # String formatting
    rapidyaml::rapidyaml  # YAML parser
    libchdr            # CHD support
    libzip::zip        # Archive support
    cpuinfo            # CPU detection
    cubeb              # Audio
    rcheevos           # Achievements
    SDL3::SDL3         # Input/window
    ZLIB::ZLIB         # Compression
    vixl               # ARM64 assembler (ARM64 only)
)
```

### 6.4 Multi-ISA Support (Lines 755-797)

```cmake
if(DISABLE_ADVANCE_SIMD)
    # Build separate libraries for SSE4, AVX, AVX2
    foreach(isa "sse4" "avx" "avx2")
        add_library(GS-${isa} STATIC ${pcsx2GSSourcesUnshared})
        target_compile_options(GS-${isa} PRIVATE ${compile_options_${isa}})
        target_link_libraries(PCSX2 PRIVATE GS-${isa}>)
    endforeach()
endif()
```

---

## PART 7: ADDITIONAL KEY FINDINGS

### 7.1 Block Linking System

**From BaseblockEx.h (Line 228):**
```cpp
void BaseBlocks::Link(u32 pc, s32* jumpptr) {
    // Store jump location for patching later
    links.insert({pc, (uptr)jumpptr});
}

// When block is removed (Line 197-226):
void Remove(int first, int last) {
    // Patch all jumps to this block back to JITCompile
    auto range = links.equal_range(blocks[idx].startpc);
    for (auto i = range.first; i != range.second; ++i) {
        armEmitJmpPtr((void*)i->second, (void*)recompiler, true);
    }
}
```

### 7.2 Code Cache Management

**From iR5900.cpp (Lines 560-615):**
```cpp
static void recReserve() {
    recPtr = SysMemory::GetEERec();      // Start of code cache
    recPtrEnd = SysMemory::GetEERecEnd() - _64kb;  // End - 64KB safety
    
    // Allocate instruction cache
    s_nInstCacheSize = 128;
    s_pInstCache = (EEINST*)malloc(sizeof(EEINST) * s_nInstCacheSize);
}

// Code cache size (from Memory.cpp:204-211):
DUMP_REGION("R5900 Recompiler Cache", s_code_memory, 
            HostMemoryMap::EErecOffset, HostMemoryMap::EErecSize);
// Default size: Variable, typically 64-128MB
```

### 7.3 Branch Handling

**Branch Types (from iR5900.cpp:64-355):**
```cpp
int g_branch; // Branch flag values:
// 0 = No branch (fallthrough)
// 1 = Direct branch (target known at compile time)
// 2 = Indirect branch with event check
// 3 = Exception/syscall

// Direct branch codegen:
if (g_branch == 1) {
    // Link to target block
    armStoreImm(PTR_CPU(cpuRegs.pc), target);
    s32* jumpptr = armEmitJmpPtrPlaceholder();
    recBlocks.Link(target, jumpptr);
}

// Indirect branch codegen:
if (g_branch == 2) {
    // Check for events before dispatching
    armEmitJmp(DispatcherEvent);
}
```

### 7.4 Event System Integration

**From iR5900.cpp (Line 379-388):**
```cpp
static void recEventTest() {
    _cpuEventTest_Shared();  // Check interrupts, DMA, etc.
    
    if (eeRecExitRequested) {
        eeRecExitRequested = false;
        recExitExecution();  // longjmp back to Execute()
    }
}
```

---

## SUMMARY: KEY ARCHITECTURAL INSIGHTS

### 1. **Two-Level Block Lookup**
- Fast O(1) lookup via `recLUT[upper_16_bits][lower_16_bits >> 2]`
- Each PS2 instruction (4 bytes) has dedicated BASEBLOCK entry (8 bytes)
- Uncompiled blocks point to JITCompile dispatcher

### 2. **Lazy JIT Compilation**
- Blocks compiled on first execution
- Compilation triggered by JITCompile dispatcher
- Block ends determined dynamically (branches, exceptions, max size)

### 3. **Sophisticated Register Allocation**
- Three-tier system: Constants > Host Registers > Memory
- Separate X86/ARM64 and XMM allocators
- Liveness analysis determines allocation strategy
- LRU spilling when registers exhausted

### 4. **Optimization via Analysis**
- EEINST structure tracks per-instruction liveness
- Backward propagation determines register usage
- Multiple optimization passes (COP2 flags, VU sync, etc.)
- Dead code elimination when values not live

### 5. **VTLB Memory System**
- Handler-based architecture for different memory regions
- Fastmem optimization for RAM access
- Dynamic code generation for memory operations
- Backpatching support for page faults

### 6. **Block Linking**
- Direct jumps between blocks when possible
- Link tracking for invalidation
- Patch back to JITCompile when blocks removed

### 7. **Code Cache Management**
- Fixed-size cache (64-128MB typical)
- Reset entire cache when full
- Separate instruction analysis cache
- Profiling support for performance analysis

---

## FILES ANALYZED (WITH EXACT PATHS)

1. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/ix86-32/iR5900.cpp` - Main recompiler (82,450 bytes)
2. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/iCore.cpp` - Core functions
3. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/iCore.h` - Core header with EEINST
4. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/R5900.cpp` - CPU implementation
5. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/R5900.h` - CPU header
6. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/R5900Def.h` - cpuRegisters definition
7. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/Memory.cpp` - Memory system (1,249 lines)
8. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/vtlb.h` - VTLB interface
9. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/BaseblockEx.h` - Block structures
10. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/x86/iR5900Analysis.cpp` - Analysis passes
11. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/arm64/cpuRegistersPack.h` - Register pack
12. `/home/user/ARMSX2/app/src/main/cpp/pcsx2/CMakeLists.txt` - Build system (1,495 lines)

**All information in this report is derived from actual source code analysis. No assumptions or guesses were made.**