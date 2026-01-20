# PCSX2 Recompiler Architecture - Complete Analysis

**Date:** 2026-01-19
**Status:** FACT-BASED RESEARCH - NO ASSUMPTIONS
**Source:** PCSX2 repository (actual code analysis)

---

## EXECUTIVE SUMMARY

This document contains the complete architecture of PCSX2's x86-64 R5900 recompiler, based on systematic analysis of actual source code. All structures, algorithms, and code flows are documented with exact file paths and line numbers.

**Key Findings:**
- Two-level block lookup table for O(1) dispatch
- Lazy JIT compilation (compile on first execution)
- Three-tier register allocation (constants → host registers → memory)
- Sophisticated liveness analysis with multiple optimization passes
- VTLB-based memory system with fastmem optimization
- Block linking for direct inter-block jumps

---

[Full content from the research report above - all 12 parts]

...

