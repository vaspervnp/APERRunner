"""Minimal test runner (no pytest needed): runs every test_* in tools/tests/test_*.py."""

import glob
import importlib
import os
import sys
import time
import traceback

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)


def main():
    failures = 0
    total = 0
    for path in sorted(glob.glob(os.path.join(HERE, "test_*.py"))):
        module = importlib.import_module(os.path.splitext(os.path.basename(path))[0])
        for name in sorted(n for n in dir(module) if n.startswith("test_")):
            total += 1
            started = time.time()
            try:
                getattr(module, name)()
                print(f"PASS  {module.__name__}.{name}  ({time.time() - started:.1f}s)")
            except Exception:
                failures += 1
                print(f"FAIL  {module.__name__}.{name}")
                traceback.print_exc()
    print(f"\n{total - failures}/{total} passed")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
