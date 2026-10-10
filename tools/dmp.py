# Minimal minidump reader: prints the faulting module/offset and the module-
# resolved return addresses found on the faulting thread's stack.
# usage: dmp.py UEMinidump.dmp
import struct, sys
d = open(sys.argv[1], 'rb').read()
sig, ver, nstreams, rva = struct.unpack_from('<IIII', d, 0)
streams = {}
for i in range(nstreams):
    t, size, r = struct.unpack_from('<III', d, rva + i*12)
    streams[t] = (size, r)
def rstr(r):
    n = struct.unpack_from('<I', d, r)[0]
    return d[r+4:r+4+n].decode('utf-16le')
mods = []
size, r = streams[4]
n = struct.unpack_from('<I', d, r)[0]
for i in range(n):
    o = r + 4 + i*108
    base, sz = struct.unpack_from('<QI', d, o)
    nr = struct.unpack_from('<I', d, o+20)[0]
    mods.append((base, sz, rstr(nr).split(chr(92))[-1]))
def where(a):
    for b, s, nm in mods:
        if b <= a < b+s: return f'{nm}+0x{a-b:x}'
    return None
size, r = streams[6]
tid = struct.unpack_from('<I', d, r)[0]
code, flags, rec, addr = struct.unpack_from('<IIQQ', d, r+8)
print('thread', tid, 'code %x' % code, 'addr', hex(addr), where(addr))
ctx_size, ctx_rva = struct.unpack_from('<II', d, r + 8 + 152)
# CONTEXT x64: Rip at 0xF8, Rsp at 0x98
rip = struct.unpack_from('<Q', d, ctx_rva + 0xF8)[0]; rsp = struct.unpack_from('<Q', d, ctx_rva + 0x98)[0]
print('rip', hex(rip), where(rip), 'rsp', hex(rsp))
# memory list to scan stack
mem = []
if 9 in streams:
    size, r = streams[9]
    n, base_rva = struct.unpack_from('<QQ', d, r)
    o = r + 16; cur = base_rva
    for i in range(n):
        st, sz = struct.unpack_from('<QQ', d, o + i*16)
        mem.append((st, sz, cur)); cur += sz
else:
    size, r = streams[5]
    n = struct.unpack_from('<I', d, r)[0]
    for i in range(n):
        st, sz, rv = struct.unpack_from('<QII', d, r + 4 + i*16)
        mem.append((st, sz, rv))
for st, sz, rv in mem:
    if st <= rsp < st+sz:
        off = rsp - st
        cnt = 0
        for p in range(rv+off, min(rv+sz, rv+off+0x4000), 8):
            v = struct.unpack_from('<Q', d, p)[0]
            w = where(v)
            if w and not w.startswith('ntdll'):
                print('  ', w); cnt += 1
                if cnt > 60: break