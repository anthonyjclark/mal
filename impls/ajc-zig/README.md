# Make-a-Lisp implemented with Zig

```bash
make "test^ajc-zig^step0" # Passing all tests
make "test^ajc-zig^step1" # Passing all tests

# Compile and run with
make STEP; and rlwrap ./STEP
```

Chores after each step:
- Check error enums to see if all are used.
- Check for memory leaks.

Resource:
- [gdb printers](https://github.com/ziglang/zig/blob/master/tools/std_gdb_pretty_printers.py) (and [this one](https://github.com/ziglang/zig/blob/master/tools/zig_gdb_pretty_printers.py))
- [lldb printers](https://github.com/ziglang/zig/blob/master/tools/lldb_pretty_printers.py)
