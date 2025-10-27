#!/usr/bin/env python3
"""Marshal Code Object Extractor for PyInstaller Bytecode Recovery"""
import sys
import marshal

def extract_code_object(pyc_path: str, output_path: str) -> int:
    """Extract code object from potentially corrupted .pyc file."""
    try:
        with open(pyc_path, 'rb') as f:
            raw = f.read()
        
        for offset in range(0, min(32, len(raw))):
            try:
                code = marshal.loads(raw[offset:])
                with open(output_path, 'wb') as out:
                    marshal.dump(code, out)
                print(f'[+] Code object extracted (header_offset={offset} bytes)')
                return 0
            except (ValueError, EOFError, TypeError):
                continue
        
        print('[-] Failed to extract valid code object', file=sys.stderr)
        return 1
    except Exception as e:
        print(f'[-] Error: {e}', file=sys.stderr)
        return 1

if __name__ == '__main__':
    if len(sys.argv) != 3:
        print('Usage: marshal_extract.py <input.pyc> <output.marshaled>', file=sys.stderr)
        sys.exit(1)
    sys.exit(extract_code_object(sys.argv[1], sys.argv[2]))
