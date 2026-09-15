#!/usr/bin/env python3
"""
Roda os testes do CullZoneCreator.lua sem precisar do GTA.

Ordem de preferencia:
  1. Um binario 'lua' ou 'luajit' no PATH (mais rapido);
  2. O modulo 'lupa' (pip install lupa), que embute o LuaJIT 2.1.

Uso:
    python3 tests/run_tests.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPT = os.path.join(ROOT, "moonloader", "CullZoneCreator.lua")
TESTS = [os.path.join(ROOT, "tests", "test_czc.lua"),
         os.path.join(ROOT, "tests", "test_ui_frames.lua")]


def run_with_lua(binary):
    print(f"[run_tests] usando {binary}")
    status = 0
    for test in TESTS:
        print(f"[run_tests] -> {os.path.basename(test)}")
        code = subprocess.call([binary, test, SCRIPT], cwd=ROOT)
        status = status or code
    return status


def run_with_lupa():
    try:
        from lupa import luajit21
    except Exception as exc:  # pragma: no cover
        print("[run_tests] lupa indisponivel:", exc)
        print("            instale com:  pip install lupa")
        return 2

    lua = luajit21.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(f"arg = {{ {SCRIPT!r} }}")
    source = open(SCRIPT, encoding="utf-8", errors="replace").read()
    try:
        lua.execute("local src = ...; local f, err = loadstring(src); if not f then error(err, 0) end", source)
    except Exception as exc:
        print("[run_tests] erro de sintaxe em CullZoneCreator.lua:", exc)
        return 1
    print("[run_tests] sintaxe OK (LuaJIT 2.1)")

    status = 0
    for test in TESTS:
        print(f"[run_tests] -> {os.path.basename(test)}")
        try:
            lua.execute("local src = ...; local f, err = loadfile(src); if not f then error(err, 0) end; f()",
                        test)
        except Exception as exc:
            print("[run_tests] FALHOU:", exc)
            status = 1
    return status


def main():
    for candidate in ("luajit", "lua5.1", "lua"):
        binary = shutil.which(candidate)
        if binary:
            return run_with_lua(binary)
    return run_with_lupa()


if __name__ == "__main__":
    sys.exit(main())
