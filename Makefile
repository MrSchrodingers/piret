# Adaptive Reverse Engineering Makefile for PyInstaller Binaries (v7.0-PRODUCTION)
#
# Critical Fix: Variable Evaluation Order
# - Uses lazy evaluation (=) for PYTHON_EXE to defer substitution
# - Forces Make restart after Python version detection
# - Prevents 'pythonauto' concatenation error
#
# Architecture:
# - Modular design with externalized Python scripts
# - Multi-tool decompilation pipeline (pycdc → uncompyle6 → pycdas)
# - Automatic Python version detection with manual fallback
# - Graceful degradation on tool failures

.DELETE_ON_ERROR:

# === Configuration ===
TARGET_EXE      := calculo_NFSe.exe

# Load persisted Python version BEFORE defining dependent variables
-include .python_version.mk

# Use conditional assignment with fallback
PYTHON_VERSION  ?= auto

# CRITICAL: Use lazy evaluation (=) not immediate (:=) to allow runtime substitution
# This defers $(PYTHON_VERSION) expansion until PYTHON_EXE is actually used
PYTHON_EXE       = python$(PYTHON_VERSION)

# === Output Paths ===
EXTRACT_DIR     := $(TARGET_EXE)_extracted
PYZ_DIR         := $(EXTRACT_DIR)/PYZ-00.pyz_extracted
DECOMPILED_DIR  := src_recovered
MAIN_PYC        := $(EXTRACT_DIR)/$(basename $(TARGET_EXE)).pyc

# === Toolchain ===
PYCDC           := ./pycdc/build/pycdc
PYCDAS          := ./pycdc/build/pycdas
UNCOMPYLE6      := $(PYTHON_EXE) -m uncompyle6.main
MARSHAL_EXTRACT := ./scripts/marshal_extract.py
PYINSTXTRACTOR_REPO   := https://github.com/extremecoders-re/pyinstxtractor.git
PYINSTXTRACTOR_DIR    := pyinstxtractor
PYINSTXTRACTOR_SCRIPT := $(PYINSTXTRACTOR_DIR)/pyinstxtractor.py

# === Targets ===
.PHONY: all clean check-env check-deps extract detect-python-version recover-source build-pycdc help

all: recover-source

help:
	@echo "Adaptive Reverse Engineering Makefile for PyInstaller Binaries (v7.0)"
	@echo ""
	@echo "Available targets:"
	@echo "  all                 – Run full recovery pipeline (default)"
	@echo "  check-env           – Validate Python environment"
	@echo "  check-deps          – Verify system dependencies"
	@echo "  build-pycdc         – Build pycdc/pycdas decompiler suite"
	@echo "  extract             – Extract PyInstaller archive"
	@echo "  detect-python-version – Auto-detect Python version"
	@echo "  recover-source      – Decompile all extracted .pyc files"
	@echo "  clean               – Remove all generated artifacts"
	@echo "  help                – Show this help message"

# === Dependency Checks ===
check-deps:
	@echo "[+] Checking system dependencies..."
	@for cmd in git cmake make g++ xxd; do \
		if ! command -v $$cmd &> /dev/null; then \
			echo "[\033[0;31m!\033[0m] FATAL: '$$cmd' not found in PATH."; \
			exit 1; \
		fi \
	done
	@echo "[\033[0;32m+\033[0m] All dependencies satisfied."

# === Python Version Detection ===
detect-python-version: $(PYINSTXTRACTOR_SCRIPT)
ifeq ($(PYTHON_VERSION),auto)
	@echo "[i] Auto-detecting Python version from $(TARGET_EXE)..."
	@rm -rf $(EXTRACT_DIR)_tmp
	@mkdir -p $(EXTRACT_DIR)_tmp
	@if ! python3 $(PYINSTXTRACTOR_SCRIPT) $(TARGET_EXE) > $(EXTRACT_DIR)_tmp/detect.log 2>&1; then \
		echo "[\033[0;31m!\033[0m] Extraction failed during auto-detection."; \
		rm -rf $(EXTRACT_DIR)_tmp; \
		echo ""; \
		echo "[?] Please specify the Python version used to build this executable."; \
		echo "    Examples: 3.12, 3.13, 3.11"; \
		echo ""; \
		echo -n "Python version: "; \
		read ver; \
		echo "PYTHON_VERSION := $$ver" > .python_version.mk; \
		echo "[\033[0;32m+\033[0m] Saved to .python_version.mk"; \
		echo "[\033[0;33m→\033[0m] Re-run 'make' to continue with Python $$ver"; \
		exit 1; \
	fi
	@ver=$$(grep -oP 'Python version: \K[0-9.]+' $(EXTRACT_DIR)_tmp/detect.log | head -1); \
	if [ -z "$$ver" ]; then \
		echo "[\033[0;31m!\033[0m] Could not parse Python version from extraction log."; \
		rm -rf $(EXTRACT_DIR)_tmp; \
		echo ""; \
		echo "[?] Please specify the Python version manually."; \
		echo -n "Python version: "; \
		read ver; \
		echo "PYTHON_VERSION := $$ver" > .python_version.mk; \
		echo "[\033[0;32m+\033[0m] Saved to .python_version.mk"; \
		echo "[\033[0;33m→\033[0m] Re-run 'make' to continue"; \
		exit 1; \
	fi; \
	echo "PYTHON_VERSION := $$ver" > .python_version.mk; \
	echo "[\033[0;32m+\033[0m] Detected Python $$ver (saved to .python_version.mk)"; \
	rm -rf $(EXTRACT_DIR)_tmp; \
	echo "[\033[0;33m→\033[0m] Restarting Make with detected version..."; \
	echo ""; \
	$(MAKE) $(MAKECMDGOALS)
	@exit 0
else
	@echo "[\033[0;32m+\033[0m] Using Python $(PYTHON_VERSION) (from .python_version.mk)"
endif

# === Environment Validation ===
check-env: detect-python-version
	@echo "[+] Validating Python $(PYTHON_VERSION) environment..."
	@if [ "$(PYTHON_VERSION)" = "auto" ]; then \
		echo "[\033[0;31m!\033[0m] ERROR: Python version still set to 'auto'"; \
		echo "    This should not happen. Please report this as a bug."; \
		exit 1; \
	fi
	@if ! command -v $(PYTHON_EXE) &> /dev/null; then \
		echo "[\033[0;31m!\033[0m] ERROR: '$(PYTHON_EXE)' not found in PATH."; \
		echo ""; \
		echo "[i] Available Python versions on this system:"; \
		command -v python3 &> /dev/null && python3 --version || echo "    python3: not found"; \
		command -v python3.12 &> /dev/null && python3.12 --version || echo "    python3.12: not found"; \
		command -v python3.13 &> /dev/null && python3.13 --version || echo "    python3.13: not found"; \
		echo ""; \
		echo "[!] Please install Python $(PYTHON_VERSION) or update .python_version.mk"; \
		exit 1; \
	fi
	@$(PYTHON_EXE) --version 2>&1 | head -1
	@echo "[\033[0;32m+\033[0m] Python $(PYTHON_VERSION) validated successfully."

# === Build pycdc Decompiler Suite ===
build-pycdc: check-deps
	@if [ ! -d "pycdc" ]; then \
		echo "[+] Cloning pycdc repository..."; \
		git clone --depth 1 https://github.com/zrax/pycdc.git; \
	fi
	@mkdir -p pycdc/build
	@cd pycdc/build && cmake -DCMAKE_BUILD_TYPE=Release .. > /dev/null
	@$(MAKE) -C pycdc/build > /dev/null 2>&1
	@if [ ! -f "$(PYCDC)" ]; then \
		echo "[\033[0;31m!\033[0m] Build failed: pycdc binary not found."; \
		exit 1; \
	fi
	@echo "[\033[0;32m+\033[0m] pycdc and pycdas built successfully."

# === Extract PyInstaller Archive ===
$(PYINSTXTRACTOR_DIR):
	@echo "[+] Cloning pyinstxtractor..."
	@git clone --depth 1 $(PYINSTXTRACTOR_REPO) $(PYINSTXTRACTOR_DIR) > /dev/null 2>&1

$(PYINSTXTRACTOR_SCRIPT): | $(PYINSTXTRACTOR_DIR)
	@chmod +x $(PYINSTXTRACTOR_SCRIPT)

extract: $(TARGET_EXE) check-env $(PYINSTXTRACTOR_SCRIPT)
	@echo "[+] Extracting PyInstaller archive: $(TARGET_EXE)"
	@rm -rf $(EXTRACT_DIR)
	@$(PYTHON_EXE) $(PYINSTXTRACTOR_SCRIPT) $(TARGET_EXE)
	@if [ ! -d "$(PYZ_DIR)" ]; then \
		echo "[\033[0;31m!\033[0m] Extraction failed: PYZ directory not found."; \
		echo "    Expected: $(PYZ_DIR)"; \
		exit 1; \
	fi
	@echo "[\033[0;32m+\033[0m] Extraction completed successfully."

# === Source Recovery Pipeline ===
recover-source: extract build-pycdc
	@echo "[+] Initializing decompilation workspace: $(DECOMPILED_DIR)"
	@mkdir -p $(DECOMPILED_DIR)
	@echo "[+] Installing Python decompilation tools..."
	@$(PYTHON_EXE) -m pip install -q uncompyle6 xdis 2>/dev/null || true
	@echo "[+] Starting multi-tool decompilation pipeline..."
	@echo ""
	@total=0; success_pycdc=0; success_uncompyle=0; disasm_only=0; \
	for pyc in $$(find $(PYZ_DIR) -name "*.pyc" 2>/dev/null); do \
		total=$$((total + 1)); \
		out="$(DECOMPILED_DIR)/$$(echo "$$pyc" | sed 's|$(PYZ_DIR)/||' | sed 's/\.pyc$$/.py/')"; \
		log="$${out%.py}.log"; \
		dis="$${out%.py}.dis"; \
		mkdir -p "$$(dirname "$$out")"; \
		echo "=== $$pyc ===" > "$$log"; \
		if $(PYCDC) "$$pyc" > "$$out" 2>> "$$log" && [ -s "$$out" ]; then \
			echo "[\033[0;32m✓\033[0m] pycdc     : $$(basename $$out)"; \
			success_pycdc=$$((success_pycdc + 1)); \
		elif $(UNCOMPYLE6) -o "$$out" "$$pyc" >> "$$log" 2>&1 && [ -s "$$out" ]; then \
			echo "[\033[0;32m✓\033[0m] uncompyle6: $$(basename $$out)"; \
			success_uncompyle=$$((success_uncompyle + 1)); \
		else \
			$(PYCDAS) "$$pyc" > "$$dis" 2>> "$$log" || true; \
			if [ -s "$$dis" ]; then \
				echo "[\033[0;33m~\033[0m] disasm    : $$(basename $$dis)"; \
				disasm_only=$$((disasm_only + 1)); \
			else \
				echo "[\033[0;31m✗\033[0m] failed    : $$(basename $$pyc)"; \
			fi; \
			rm -f "$$out"; \
			if [ -f "$(MARSHAL_EXTRACT)" ] && [ -s "$$pyc" ]; then \
				$(PYTHON_EXE) $(MARSHAL_EXTRACT) "$$pyc" "/tmp/code_$$$$.marshaled" >> "$$log" 2>&1 && \
				$(PYCDAS) -c "/tmp/code_$$$$.marshaled" > "$${dis%.dis}_raw.dis" 2>> "$$log" && \
				rm -f "/tmp/code_$$$$.marshaled" || true; \
			fi; \
		fi; \
	done; \
	echo ""; \
	echo "======================================================================"; \
	echo "[\033[0;32m+\033[0m] DECOMPILATION STATISTICS"; \
	echo "======================================================================"; \
	echo "  Total files processed:    $$total"; \
	echo "  Decompiled (pycdc):       $$success_pycdc"; \
	echo "  Decompiled (uncompyle6):  $$success_uncompyle"; \
	echo "  Disassembly only:         $$disasm_only"; \
	echo "  Failed:                   $$((total - success_pycdc - success_uncompyle - disasm_only))"; \
	echo "======================================================================"
	@if [ -f "$(MAIN_PYC)" ]; then \
		echo ""; \
		echo "[+] Processing main entry point: $(MAIN_PYC)"; \
		out="$(DECOMPILED_DIR)/$(basename $(TARGET_EXE:.exe=)).py"; \
		log="$(DECOMPILED_DIR)/$(basename $(TARGET_EXE:.exe=)).log"; \
		dis="$(DECOMPILED_DIR)/$(basename $(TARGET_EXE:.exe=)).dis"; \
		echo "=== Main Entry Point ===" > "$$log"; \
		if $(PYCDC) "$(MAIN_PYC)" > "$$out" 2>> "$$log" && [ -s "$$out" ]; then \
			echo "[\033[0;32m✓\033[0m] Main entry decompiled: $$out"; \
		elif $(UNCOMPYLE6) -o "$$out" "$(MAIN_PYC)" >> "$$log" 2>&1 && [ -s "$$out" ]; then \
			echo "[\033[0;32m✓\033[0m] Main entry decompiled (uncompyle6): $$out"; \
		else \
			$(PYCDAS) "$(MAIN_PYC)" > "$$dis" 2>> "$$log" || true; \
			echo "[\033[0;33m~\033[0m] Main entry disassembled: $$dis"; \
		fi; \
	fi
	@echo ""
	@echo "======================================================================"
	@echo "[\033[0;32m+\033[0m] REVERSE ENGINEERING PIPELINE COMPLETED"
	@echo "======================================================================"
	@echo "  Recovered source: $(DECOMPILED_DIR)/"
	@echo "  Disassembly files: *.dis (for manual analysis)"
	@echo "  Log files: *.log (detailed decompilation logs)"
	@echo "======================================================================"
	@echo ""

# === Cleanup ===
clean:
	@echo "[+] Cleaning all generated artifacts..."
	@rm -rf $(EXTRACT_DIR) $(DECOMPILED_DIR) .python_version.mk pycdc $(PYINSTXTRACTOR_DIR) scripts /tmp/code_*.marshaled
	@echo "[\033[0;32m+\033[0m] Cleanup completed."
