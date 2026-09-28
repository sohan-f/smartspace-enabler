#!/usr/bin/env python3
"""Verify APK structure: classes.dex + META-INF/xposed metadata present."""
import sys
import zipfile

REQUIRED = [
    'classes.dex',
    'META-INF/xposed/java_init.list',
    'META-INF/xposed/module.prop',
    'META-INF/xposed/scope.list',
]

def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <apk>")
        sys.exit(1)

    apk = sys.argv[1]
    with zipfile.ZipFile(apk, 'r') as z:
        names = set(z.namelist())
        ok = True
        for req in REQUIRED:
            if req in names:
                print(f"  ✓ {req}")
            else:
                print(f"  ✗ {req} MISSING")
                ok = False
        if not ok:
            sys.exit(1)
        print("  All required entries present.")

if __name__ == '__main__':
    main()
