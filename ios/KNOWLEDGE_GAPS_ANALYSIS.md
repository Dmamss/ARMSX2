# Knowledge Gaps Analysis - Path to 100% Confidence

**Date:** 2026-01-19
**Current Confidence:** 75%
**Target Confidence:** 100%
**Status:** INCOMPLETE - DO NOT CODE YET

---

## Executive Summary

We have **25% unknown territory** across 8 critical areas. Each gap must be completely closed before implementation begins.

---

## Gap Category 1: ARM64 Instruction Encoding (15% gap)

### ✅ What We Know
- Fixed 32-bit instruction format
- Basic register encoding (5-bit fields)
- Simple immediate encoding (12-bit)
- Branch offset calculation concept

### ❌ What We DON'T Know

**1.1 Immediate Encoding Edge Cases**
- ❓ How to encode immediates > 4095 in ADD/SUB?
- ❓ What happens with negative immediates?
- ❓ Logical immediate encoding (complex bitmask patterns)
- ❓ Floating-point immediate encoding (special 8-bit format)

**Example unknown:**
```cpp
// How do we encode this?
ADD X0, X1, #100000  // Immediate too large for 12 bits

// Options:
// A) Multiple ADD instructions?
// B) Load into temp register first?
// C) Use MOVZ + ADD pattern?
```

**1.2 Addressing Mode Encoding**
- ❓ Pre-index: `LDR X0, [X1, #8]!` (writes back address)
- ❓ Post-index: `LDR X0, [X1], #8` (loads then increments)
- ❓ Register offset: `LDR X0, [X1, X2]`
- ❓ Scaled register offset: `LDR X0, [X1, X2, LSL #3]`

**1.3 Condition Code Flags**
- ❓ Which instructions set flags (S suffix)?
- ❓ How to encode flag-setting variants?
- ❓ NZCV flag meaning and usage

**1.4 Shift/Extend Encodings**
- ❓ LSL/LSR/ASR/ROR in data processing instructions
- ❓ SXTW/UXTW/SXTH/UXTH sign/zero extension
- ❓ When can shifts be folded into instructions?

**1.5 SIMD/NEON Instruction Encoding**
- ❓ Vector register encoding (different from scalar)
- ❓ Element size specification (.4S, .2D, .16B, etc.)
- ❓ Lane indexing for vector element operations

**Action Required:**
- [ ] Study ARM Architecture Reference Manual sections on encoding
- [ ] Create encoding test suite (verify against assembler)
- [ ] Document every edge case with examples
- [ ] Build encoding reference table

**Estimated Time to Close Gap:** 3-5 days

---

## Gap Category 2: iOS Memory Management Integration (30% gap)

### ✅ What We Know
- vm_remap creates dual RW/RX mappings
- LuckTXM strategy (512MB pre-allocated)
- LuckNoTXM strategy (per-allocation)
- Basic mmap/mprotect usage

### ❌ What We DON'T Know

**2.1 LuckTXM Implementation Details**
- ❓ Exact sequence of vm_remap calls
- ❓ How to handle vm_remap failures?
- ❓ What are the mach_port parameters?
- ❓ How to verify mirror is working?

**Example unknown:**
```objc
// What are the exact parameters?
kern_return_t kr = vm_remap(
    mach_task_self(),           // target_task - is this correct?
    &rw_address,                // address - output or input?
    size,                       // size - page-aligned?
    0,                          // mask - what should this be?
    VM_FLAGS_ANYWHERE,          // flags - correct?
    mach_task_self(),           // src_task - always self?
    rx_address,                 // memory - source address
    FALSE,                      // copy - FALSE = mirror, TRUE = copy
    &cur_protection,            // cur_protection - output?
    &max_protection,            // max_protection - output?
    VM_INHERIT_NONE             // inheritance - correct?
);

// If kr != KERN_SUCCESS, what's the fallback?
// How do we clean up partial allocations?
```

**2.2 Code Buffer Management**
- ❓ How to track RX vs RW pointers during emission?
- ❓ When to switch between RX and RW?
- ❓ How to handle buffer overflow?
- ❓ Alignment requirements (16-byte? page-aligned?)

**2.3 Instruction Cache Coherency**
- ❓ When exactly to call sys_icache_invalidate?
- ❓ How much to invalidate (range? whole buffer?)
- ❓ Performance impact of cache flushing
- ❓ ARM64 cache line size (64 bytes? 128 bytes?)

**2.4 TXM Mode Differences**
- ❓ What changes between LuckTXM and LuckNoTXM code emission?
- ❓ How to detect at runtime which mode is active?
- ❓ Can we switch modes mid-execution?

**2.5 Memory Limits**
- ❓ iOS app memory limits (varies by device)
- ❓ JIT code cache size recommendations
- ❓ When to evict old blocks?
- ❓ How to handle fragmentation?

**Action Required:**
- [ ] Read Mach kernel documentation (vm_remap, vm_protect, etc.)
- [ ] Study DolphinOS MemoryUtil_iOS.cpp line-by-line
- [ ] Create test program that allocates RW/RX mirrors
- [ ] Verify cache invalidation is working
- [ ] Test on real iOS device (simulator != device)

**Estimated Time to Close Gap:** 4-6 days

---

## Gap Category 3: MIPS R5900 Architecture Specifics (20% gap)

### ✅ What We Know
- Basic R-type, I-type, J-type formats
- Common instructions (ADD, SUB, LW, SW)
- 32 general-purpose registers
- HI/LO registers for multiply/divide

### ❌ What We DON'T Know

**3.1 R5900 vs Standard MIPS Differences**
- ❓ 128-bit GPR extension (quadword operations)
- ❓ Multimedia Instructions (MMI) - complete set
- ❓ COP0 (system control) register set
- ❓ COP1 (FPU) differences from MIPS IV
- ❓ COP2 (VU0 macro mode) integration

**Example unknown:**
```cpp
// R5900 has 128-bit registers, but instructions operate on:
// - 32-bit portions (standard MIPS)
// - 64-bit portions (doubleword)
// - 128-bit portions (quadword)

// How do we track 128-bit state in 64-bit ARM64 registers?
// Do we split each MIPS register into two ARM64 registers?
// Or keep upper 64 bits in memory?
```

**3.2 Delay Slots**
- ❓ Branch delay slot exact semantics
- ❓ Load delay slots (R5900 has these!)
- ❓ Can delay slot instruction be nullified?
- ❓ Branch-likely instructions (BEQL, BNEL)

**3.3 Exception Handling**
- ❓ Overflow exceptions (ADD vs ADDU)
- ❓ TLB miss handling
- ❓ Break/Syscall instructions
- ❓ Cop unusable exceptions

**3.4 Memory System**
- ❓ PS2 memory map (32MB RAM, VRAM, scratchpad, BIOS)
- ❓ Uncached/cached memory regions
- ❓ DMA interactions with CPU
- ❓ Cache instruction behavior (CACHE opcode)

**3.5 Floating-Point Peculiarities**
- ❓ R5900 FPU is NOT IEEE 754 compliant
- ❓ Differences from standard MIPS FPU
- ❓ Flush-to-zero behavior
- ❓ Condition code register (FCR31)

**Action Required:**
- [ ] Read R5900 Core Instruction Set Manual (complete, not just summary)
- [ ] Study PCSX2 R5900.cpp/h thoroughly
- [ ] Create R5900 instruction reference table
- [ ] Document every R5900-specific extension
- [ ] Test PCSX2 interpreter behavior for edge cases

**Estimated Time to Close Gap:** 5-7 days

---

## Gap Category 4: Register Allocation Strategy (20% gap)

### ✅ What We Know
- LRU eviction concept
- Cache register state in ARM64 registers
- Flush on block boundaries

### ❌ What We DON'T Know

**4.1 Register Pressure Analysis**
- ❓ How many ARM64 registers can we actually use?
- ❓ Which registers must be preserved (calling convention)?
- ❓ How to handle spilling when all registers full?
- ❓ Cost model (register access vs memory access)

**ARM64 iOS Calling Convention (we need exact specification):**
```
X0-X7:   Argument/result registers (CALLER-SAVED)
X8:      Indirect result location (CALLER-SAVED)
X9-X15:  Temporary registers (CALLER-SAVED)
X16-X17: Intra-procedure-call scratch (CALLER-SAVED)
X18:     PLATFORM REGISTER (RESERVED - DO NOT USE)
X19-X28: Callee-saved registers (MUST PRESERVE)
X29:     Frame pointer (FP) (MUST PRESERVE)
X30:     Link register (LR) (MUST PRESERVE)
SP:      Stack pointer (MUST PRESERVE)

Usable for MIPS state:
- X9-X15 (7 regs) - temps, don't need to preserve
- X19-X28 (10 regs) - can use but must save/restore

Total: 17 usable registers
```

**Questions:**
- ❓ Do we save X19-X28 in prologue/epilogue?
- ❓ Or do we use JIT entry wrapper to save them?
- ❓ What about D8-D15 (callee-saved FP regs)?

**4.2 Constant Propagation**
- ❓ How to track constant values?
- ❓ When to fold constants vs keep in register?
- ❓ How to invalidate constants?

**4.3 Liveness Analysis**
- ❓ Which registers are live at each instruction?
- ❓ Backward vs forward liveness analysis?
- ❓ How to handle control flow (branches)?

**4.4 Register Mapping Strategy**
- ❓ Static allocation (fixed MIPS→ARM64 mapping)?
- ❓ Dynamic allocation (allocate on demand)?
- ❓ Hybrid approach?

**Example:**
```cpp
// Static allocation example:
X19 = MIPS $zero (always 0)
X20 = MIPS $at (assembler temporary)
X21 = MIPS $v0 (function return value)
... etc

// OR dynamic allocation:
Allocate ARM64 regs on demand, track with array
```

**Action Required:**
- [ ] Read ARM64 procedure call standard (AAPCS64)
- [ ] Study PCSX2's register allocator (iR5900.cpp)
- [ ] Design allocation algorithm specific to ARM64
- [ ] Create allocation test cases
- [ ] Profile allocation vs spilling tradeoffs

**Estimated Time to Close Gap:** 3-4 days

---

## Gap Category 5: Block Compilation Strategy (15% gap)

### ✅ What We Know
- Compile until branch instruction
- Include delay slot in block
- Store compiled blocks in cache

### ❌ What We DON'T Know

**5.1 Block Termination Conditions**
- ❓ Always end at branch? Or allow fall-through?
- ❓ Maximum block size?
- ❓ How to handle self-modifying code?
- ❓ When to recompile blocks?

**5.2 Block Linking**
- ❓ Direct vs indirect linking
- ❓ How to patch branch targets?
- ❓ Handling conditional vs unconditional branches
- ❓ Return address prediction

**Example:**
```cpp
// Block A ends with: J BlockB_address
// Options:
// A) Emit: armAsm->B(interpreter_dispatch)  // Slow
// B) Emit: armAsm->B(BlockB_compiled)       // Fast, requires linking
// C) Emit: armAsm->BL(lookup_and_jump)      // Medium
```

**5.3 Invalidation Strategy**
- ❓ How to detect code modification?
- ❓ Invalidate single block or all blocks?
- ❓ Hash-based vs address-based tracking?

**5.4 Prologue/Epilogue Code**
- ❓ What goes in prologue? (save registers, setup)
- ❓ What goes in epilogue? (restore, return)
- ❓ Do we need stack frame?

**5.5 Exception Handling in Blocks**
- ❓ How to exit block on exception?
- ❓ Preserving PC for exception handler
- ❓ Unwinding JIT stack

**Action Required:**
- [ ] Study PCSX2's block management (iCore.cpp)
- [ ] Design block lifecycle (create, link, invalidate, evict)
- [ ] Create block metadata structure
- [ ] Plan exception handling strategy
- [ ] Test block linking performance

**Estimated Time to Close Gap:** 3-4 days

---

## Gap Category 6: PCSX2 Integration (25% gap)

### ✅ What We Know
- PCSX2Wrapper exists (stub functions)
- PCSX2 has interpreter we can reference
- PCSX2 has x86-64 recompiler

### ❌ What We DON'T Know

**6.1 PCSX2 Build System**
- ❓ How to actually build PCSX2 core for iOS?
- ❓ CMake configuration for ARM64?
- ❓ Dependencies (wxWidgets, etc.)?
- ❓ What parts of PCSX2 do we actually need?

**6.2 PCSX2 Memory System**
- ❓ How does PCSX2 manage PS2 memory?
- ❓ How to hook JIT memory accesses into PCSX2 memory?
- ❓ TLB implementation?
- ❓ Memory mapping functions?

**6.3 PCSX2 CPU State Structure**
- ❓ Where are MIPS registers stored (cpuRegs struct)?
- ❓ How to access from JIT code?
- ❓ Thread safety?

**Example unknown:**
```cpp
// We need something like:
extern cpuRegisters cpuRegs;  // Global PS2 CPU state

// In JIT code, we need to:
// 1. Read cpuRegs.GPR.r[rs] when register not cached
// 2. Write cpuRegs.GPR.r[rd] when evicting register
// 3. Access cpuRegs.pc for exception handling

// But:
// - Where is cpuRegs defined?
// - Is it thread-local?
// - What's the exact struct layout?
```

**6.4 PCSX2 Function Interfaces**
- ❓ How to call PCSX2 memory read/write functions from JIT?
- ❓ How to trigger exceptions from JIT?
- ❓ How to interface with BIOS/kernel?

**6.5 PCSX2 Existing Recompiler Code Reusability**
- ❓ Can we reuse decoder tables?
- ❓ Can we reuse instruction analysis?
- ❓ Can we reuse optimization passes?

**Action Required:**
- [ ] Clone PCSX2 repository
- [ ] Attempt to build PCSX2 core for ARM64 macOS first
- [ ] Identify minimum required PCSX2 components
- [ ] Document all PCSX2 interfaces we'll need
- [ ] Create abstraction layer design

**Estimated Time to Close Gap:** 7-10 days (CRITICAL PATH)

---

## Gap Category 7: Performance & Optimization (10% gap)

### ✅ What We Know
- JIT should be faster than interpreter
- Block linking improves performance
- Register caching reduces memory accesses

### ❌ What We DON'T Know

**7.1 Fastmem Strategy**
- ❓ How to implement fastmem on iOS?
- ❓ Backpatching for access violations?
- ❓ Performance gain estimation?

**7.2 Micro-Optimizations**
- ❓ Which MIPS instruction patterns are common?
- ❓ Peephole optimization opportunities?
- ❓ ARM64-specific optimization tricks?

**7.3 Profiling & Measurement**
- ❓ How to measure JIT performance?
- ❓ What metrics to track?
- ❓ Profiling on iOS device?

**7.4 Compilation Speed vs Execution Speed**
- ❓ How long can compilation take?
- ❓ Tiered compilation (fast compile first, optimize later)?
- ❓ When to give up and use interpreter?

**Action Required:**
- [ ] Study iOS fastmem implementations (if any)
- [ ] Profile PCSX2 to find hottest code paths
- [ ] Create performance measurement framework
- [ ] Design optimization strategy

**Estimated Time to Close Gap:** 2-3 days (can defer initially)

---

## Gap Category 8: Testing & Validation (20% gap)

### ✅ What We Know
- Need to test each instruction
- Compare against interpreter
- Test on real device

### ❌ What We DON'T Know

**8.1 Test Infrastructure**
- ❓ How to create isolated instruction tests?
- ❓ How to verify ARM64 encoding correctness?
- ❓ How to compare JIT vs interpreter results?

**8.2 Test Coverage**
- ❓ Which instructions to prioritize?
- ❓ Edge cases to test (overflow, exceptions, etc.)?
- ❓ Regression test suite?

**8.3 Debugging Tools**
- ❓ How to dump generated ARM64 code?
- ❓ How to disassemble JIT output?
- ❓ How to trace JIT execution?

**8.4 Device Testing**
- ❓ How to deploy to iOS device?
- ❓ How to debug on device?
- ❓ Different iOS versions to test?

**Action Required:**
- [ ] Design test framework architecture
- [ ] Create ARM64 encoding validator
- [ ] Build instruction-level test cases
- [ ] Set up device testing pipeline

**Estimated Time to Close Gap:** 4-5 days

---

## TOTAL GAP CLOSURE TIMELINE

| Gap Category | Confidence | Days to Close | Priority |
|--------------|-----------|---------------|----------|
| 1. ARM64 Encoding | 85% → 100% | 3-5 days | HIGH |
| 2. iOS Memory Mgmt | 70% → 100% | 4-6 days | CRITICAL |
| 3. MIPS R5900 | 80% → 100% | 5-7 days | HIGH |
| 4. Register Allocation | 80% → 100% | 3-4 days | HIGH |
| 5. Block Compilation | 85% → 100% | 3-4 days | MEDIUM |
| 6. PCSX2 Integration | 75% → 100% | **7-10 days** | **CRITICAL PATH** |
| 7. Performance | 90% → 100% | 2-3 days | LOW (defer) |
| 8. Testing | 80% → 100% | 4-5 days | MEDIUM |

**TOTAL: 31-44 days of deep study required**

**Critical Path Items (MUST DO FIRST):**
1. PCSX2 Integration (7-10 days) - **BLOCKS EVERYTHING**
2. iOS Memory Management (4-6 days) - **REQUIRED FOR TESTING**
3. MIPS R5900 (5-7 days) - **REQUIRED FOR DECODING**

---

## KNOWLEDGE VERIFICATION CHECKLIST

Before proceeding to implementation, we must be able to answer YES to ALL of these:

### ARM64 Encoding
- [ ] Can encode ANY ARM64 instruction manually
- [ ] Understand ALL addressing modes
- [ ] Know exact bit layout of each instruction type
- [ ] Can handle large immediates correctly
- [ ] Understand SIMD/NEON encoding

### iOS Memory
- [ ] Successfully created RW/RX mirror on test device
- [ ] Understand all vm_remap parameters
- [ ] Know when to call sys_icache_invalidate
- [ ] Tested code execution from RX buffer
- [ ] Handled all error cases

### MIPS R5900
- [ ] Read complete R5900 manual
- [ ] Documented all R5900-specific extensions
- [ ] Know delay slot semantics precisely
- [ ] Understand exception handling
- [ ] Mapped all 256+ instructions

### Register Allocation
- [ ] Know exact ARM64 calling convention
- [ ] Designed allocation algorithm
- [ ] Implemented liveness analysis
- [ ] Tested spilling strategy
- [ ] Profiled allocation overhead

### Block Compilation
- [ ] Defined block termination rules
- [ ] Designed linking strategy
- [ ] Planned invalidation mechanism
- [ ] Created prologue/epilogue templates
- [ ] Tested block execution

### PCSX2 Integration
- [ ] Built PCSX2 core for ARM64
- [ ] Identified all required interfaces
- [ ] Documented memory system integration
- [ ] Can access cpuRegs from JIT
- [ ] Tested basic PCSX2 functionality

### Testing
- [ ] Created encoding test suite
- [ ] Built instruction validator
- [ ] Designed test framework
- [ ] Set up device testing
- [ ] Can compare JIT vs interpreter

---

## NEXT ACTIONS (NO CODING YET)

**Week 1-2: PCSX2 Deep Dive**
1. Clone PCSX2, build for macOS ARM64
2. Study entire R5900 implementation
3. Document all interfaces we need
4. Create integration design doc

**Week 3: iOS Memory Testing**
1. Create standalone test app
2. Test vm_remap on real iOS device
3. Verify RW/RX mirror works
4. Test cache invalidation

**Week 4: MIPS R5900 Study**
1. Read R5900 manual cover-to-cover
2. Create instruction reference table
3. Map all instructions to ARM64 equivalents
4. Document edge cases

**Week 5: ARM64 Encoding Mastery**
1. Study ARM Architecture Reference Manual
2. Create encoding reference implementation
3. Test against ARM assembler
4. Document all edge cases

**Week 6: Final Design**
1. Create complete architecture document
2. Design all interfaces
3. Create implementation plan
4. Get approval before coding

---

## STATUS: NOT READY TO CODE

**Current State:** 75% confidence (NOT ACCEPTABLE)
**Required State:** 100% confidence + working prototypes
**Estimated Time to Ready:** **6+ weeks of study and testing**

**DO NOT PROCEED WITH IMPLEMENTATION UNTIL ALL GAPS CLOSED**
