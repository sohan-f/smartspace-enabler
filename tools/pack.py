#!/usr/bin/env python3
"""Add DEX + META-INF files into an aapt2-produced base APK."""
import sys
import zipfile

def main():
    if len(sys.argv) < 4:
        print(f"Usage: {sys.argv[0]} <base.apk> <out.apk> <src:dst> [...]")
        sys.exit(1)

    base_apk = sys.argv[1]
    out_apk = sys.argv[2]
    entries = sys.argv[3:]

    with zipfile.ZipFile(base_apk, 'r') as base:
        names = base.namelist()
        with zipfile.ZipFile(out_apk, 'w', zipfile.ZIP_DEFLATED) as out:
            for name in names:
                out.writestr(name, base.read(name))
            for entry in entries:
                src, dst = entry.split(':', 1)
                with open(src, 'rb') as f:
                    out.writestr(dst, f.read())

if __name__ == '__main__':
    main()
