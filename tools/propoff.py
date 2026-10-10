# Reads reflected property offsets from the FGenericPropertyParams structs in the exe.
# usage: propoff.py Atlas-Win64-Shipping.exe publics.txt UAtlasThrowableResolver   (classes or structs, e.g. FAtlasMovementThrusterLinear)
# UE 5.4: {const char* Name; const char* RepNotify; uint64 PropertyFlags;
#          uint32 GenFlags; uint32 ObjectFlags; void* Setter; void* Getter;
#          uint16 ArrayDim; uint16 Offset; ...}
import struct, sys, re
exe, pub, cls = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(exe, 'rb').read()
e = struct.unpack_from('<I', data, 0x3C)[0]
nsec = struct.unpack_from('<H', data, e + 6)[0]
opt = struct.unpack_from('<H', data, e + 20)[0]
secs = []
for i in range(nsec):
    o = e + 24 + opt + i * 40
    vsize, va, rsize, rptr = struct.unpack_from('<IIII', data, o + 8)
    secs.append((va, max(vsize, rsize), rptr))
def off(r):
    for va, sz, rp in secs:
        if va <= r < va + sz: return r - va + rp
pat = re.compile(r'\?NewProp_([A-Za-z0-9_]+)@Z_Construct_U(?:Class|ScriptStruct)_%s_Statics@@2U(F\w+PropertyParams)' % cls)
rows = []
for line in open(pub, encoding='utf-8'):
    a, _f, n = line.rstrip('\n').split('\t', 2)
    m = pat.match(n)
    if m:
        o = off(int(a, 16))
        arrdim, offset = struct.unpack_from('<HH', data, o + 48)
        rows.append((offset, m.group(1), m.group(2)))
for offset, name, t in sorted(rows):
    print('0x%04x  %-45s %s' % (offset, name, t))
