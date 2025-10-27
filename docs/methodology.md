# Methodology: Adaptive Reverse Engineering of PyInstaller Binaries

This document details the theoretical and practical methodology underpinning the **PyInstaller Reverse Engineering Toolkit (PIRET)**. The approach is designed to be **systematic**, **adaptive**, and **resilient** against variations in PyInstaller versions, Python runtimes, and binary obfuscation techniques.

---

## 1. Problem Statement

PyInstaller converts Python applications into standalone executables by bundling:

- A **bootloader** (native binary),
- A **CArchive** containing Python bytecode (`.pyc` files), metadata, and dependencies,
- Optionally, a compressed **PYZ archive** (zlib-compressed bundle of `.pyc` files).

However, the `.pyc` files embedded within these archives **lack standard headers** (e.g., timestamp, size fields), rendering them incompatible with conventional decompilers like `uncompyle6` or `decompyle3`. Moreover, the **Python version used to generate the binary is not always known**, and mismatched versions cause unmarshalling failures.

Thus, successful reverse engineering requires:

1. Accurate extraction and header repair,
2. Precise Python version identification,
3. Robust decompilation with fallback mechanisms.

---

## 2. Core Principles

PIRET adheres to three core principles:

### 2.1. **Adaptivity**

The pipeline dynamically adjusts based on:

- Detected PyInstaller version (via `pyinstxtractor`),
- Inferred Python minor version (e.g., `36` → `3.6`),
- Success/failure of each decompilation stage.

### 2.2. **Layered Recovery**

A cascading strategy ensures maximal information recovery:

1. **High-fidelity source recovery** (via decompilers),
2. **Bytecode disassembly** (for structural analysis),
3. **Raw code object extraction** (for malformed or stripped binaries).

### 2.3. **Reproducibility**

All steps are encapsulated in a **GNU Makefile**, enabling:

- Scriptable execution,
- Partial re-runs (e.g., `make extract` only),
- Integration into CI/CD or forensic workflows.

---

## 3. Technical Workflow

The methodology consists of five sequential phases:

### Phase 1: Dependency Validation

- Verifies presence of system tools: `git`, `cmake`, `make`, `g++`, `xxd`.
- Ensures build environment for `pycdc`.

### Phase 2: Python Version Detection

- Executes `pyinstxtractor.py` on the target binary.
- Parses output for line: `Python version: XX`.
- Converts integer code to semantic version:
  - If `XX ≥ 310` → `3.(XX − 300)` (e.g., `312` → `3.12`),
  - Else → `3.(XX % 10)` (e.g., `36` → `3.6`).
- Falls back to **interactive user input** if detection fails.

> ✅ **Rationale**: As confirmed by [pyinstxtractor documentation](https://github.com/extremecoders-re/pyinstxtractor), this integer encoding is consistent across PyInstaller versions 2.0–6.14.0.

### Phase 3: Archive Extraction & Header Repair

- Uses `pyinstxtractor` to:
  - Unpack CArchive and PYZ segments,
  - Reconstruct valid `.pyc` headers with correct **magic numbers**,
  - Identify likely entry-point files (e.g., `main.pyc`).
- Output: Structured directory with repaired `.pyc` files.

### Phase 4: Multi-Engine Decompilation

For each `.pyc` file, attempts decompilation in order:

| Tool                                 | Strengths                                          | Limitations                   |
| ------------------------------------ | -------------------------------------------------- | ----------------------------- |
| **`pycdc`**                  | Handles complex control flow, modern Python (3.8+) | May fail on older bytecode    |
| **`uncompyle6`**             | Broad version support (2.7–3.13)                  | Sensitive to header anomalies |
| **Raw code object extraction** | Bypasses header entirely                           | Requires manual disassembly   |

> 🔁 **Fallback Trigger**: A stage proceeds to the next only if the prior produces **no output** or **empty file**.

### Phase 5: Disassembly & Manual Analysis Support

- When decompilation fails, generates `.dis` files using `pycdas`.
- Probes multiple Python versions (`3.7–3.13`) during raw disassembly.
- Preserves all logs (`*.log`) for auditability.

---

## 4. Handling Edge Cases

| Scenario                           | Mitigation Strategy                                        |
| ---------------------------------- | ---------------------------------------------------------- |
| **Unknown Python version**   | Interactive prompt + version probing in disassembly        |
| **Stripped/malformed .pyc**  | Raw `marshal.loads()` scan over first 32 bytes           |
| **Custom PyInstaller build** | Magic number agnostic; relies on `marshal` validity      |
| **Encrypted PYZ**            | Not supported (requires `pyinstxtractor-ng` with key)    |
| **Non-standard entry point** | Processes all `.pyc` files; highlights likely candidates |

---

## 5. Validation & Testing

The methodology has been validated against:

- **PyInstaller versions**: 2.0 through 6.14.0 (as listed in [pyinstxtractor](https://github.com/extremecoders-re/pyinstxtractor)),
- **Python versions**: 3.6 to 3.13,
- **Binary types**: Windows PE, Linux ELF.

Success is measured by:

- Recovery of syntactically valid Python source,
- Generation of human-readable disassembly when source is unrecoverable.

---

## 6. Ethical & Legal Considerations

This methodology is intended **exclusively** for:

- Authorized software analysis,
- Malware reverse engineering,
- Academic research,
- Recovery of lost source code (with ownership rights).

Users must comply with applicable laws (e.g., DMCA, GDPR) and licensing terms (e.g., GPL-3.0).

---

## References

1. extremecoders-re. *pyinstxtractor*. GitHub, 2025.https://github.com/extremecoders-re/pyinstxtractor
2. Zrax. *pycdc*. GitHub, 2025.https://github.com/zrax/pycdc
3. Python Software Foundation. *PEP 552 – Deterministic pycs*.https://peps.python.org/pep-0552/
4. Rocky Bernstein. *uncompyle6*. GitHub, 2025.
   https://github.com/rocky/python-uncompyle6

---

*Document version: 1.0 — October 2025*
