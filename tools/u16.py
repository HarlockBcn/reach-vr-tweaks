# Searches UTF-16LE strings (e.g. console variables, TEXT() literals) in a binary.
# usage: u16.py Atlas-Win64-Shipping.exe "regex"
import re, sys, mmap
f = open(sys.argv[1], 'rb'); m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
pat = re.compile(rb'(?:[\x20-\x7e]\x00){4,}')
kw = re.compile(sys.argv[2], re.I)
seen = set()
for x in pat.finditer(m):
    s = x.group().decode('utf-16le')
    if kw.search(s) and s not in seen:
        seen.add(s); print(hex(x.start()), s)
