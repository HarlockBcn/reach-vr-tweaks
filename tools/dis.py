# Disassembles exe functions whose symbol name contains a pattern (uses publics.txt
# from pdbpub.py). Calls and RIP-relative operands are annotated with symbols.
# usage: dis.py Atlas-Win64-Shipping.exe publics.txt "?ApplyWeight@UAtlasThrowableResolver" [max_instr]
# requires: pip install capstone
import struct, sys, bisect
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

exe_path, pub_path, pattern = sys.argv[1], sys.argv[2], sys.argv[3]
max_ins = int(sys.argv[4]) if len(sys.argv) > 4 else 400

data = open(exe_path, 'rb').read()
e = struct.unpack_from('<I', data, 0x3C)[0]
nsec = struct.unpack_from('<H', data, e + 6)[0]
opt = struct.unpack_from('<H', data, e + 20)[0]
image_base = struct.unpack_from('<Q', data, e + 24 + 24)[0]
secs = []
for i in range(nsec):
    o = e + 24 + opt + i * 40
    vsize, va, rsize, rptr = struct.unpack_from('<IIII', data, o + 8)
    secs.append((va, max(vsize, rsize), rptr))

def rva2off(r):
    for va, sz, rp in secs:
        if va <= r < va + sz:
            return r - va + rp
    return None

rvas, names = [], []
for line in open(pub_path, encoding='utf-8'):
    a, _f, n = line.rstrip('\n').split('\t', 2)
    rvas.append(int(a, 16)); names.append(n)
order = sorted(range(len(rvas)), key=lambda i: rvas[i])
srvas = [rvas[i] for i in order]; snames = [names[i] for i in order]

def sym(r):
    i = bisect.bisect_right(srvas, r) - 1
    if i >= 0 and r - srvas[i] < 0x4000:
        n = snames[i]
        return n if r == srvas[i] else '%s+0x%x' % (n, r - srvas[i])
    return None

md = Cs(CS_ARCH_X86, CS_MODE_64)
targets = [(srvas[i], snames[i]) for i in range(len(srvas)) if pattern in snames[i]]
for r, n in targets:
    nxt = srvas[bisect.bisect_right(srvas, r)] if bisect.bisect_right(srvas, r) < len(srvas) else r + 0x1000
    size = min(nxt - r, 0x3000)
    off = rva2off(r)
    print('=' * 100)
    print('%s  rva=%x size=%x' % (n, r, size))
    code = data[off:off + size]
    k = 0
    for ins in md.disasm(code, image_base + r):
        note = ''
        if ins.mnemonic in ('call', 'jmp') or 'rip' in ins.op_str:
            try:
                if ins.mnemonic in ('call', 'jmp') and ins.op_str.startswith('0x'):
                    t = int(ins.op_str, 16) - image_base
                    s = sym(t); note = s or ''
                elif 'rip' in ins.op_str:
                    import re
                    mm = re.search(r'rip ([+-]) (0x[0-9a-f]+)', ins.op_str)
                    if mm:
                        d = int(mm.group(2), 16) * (1 if mm.group(1) == '+' else -1)
                        t = ins.address + ins.size + d - image_base
                        s = sym(t)
                        if s: note = s
                        else:
                            o2 = rva2off(t)
                            if o2 and 'xmm' in ins.op_str or (o2 and 'ss' in ins.mnemonic):
                                note = 'float=%g' % struct.unpack_from('<f', data, o2)[0]
            except Exception:
                pass
        print('  %x: %-8s %-50s %s' % (ins.address - image_base, ins.mnemonic, ins.op_str, note))
        k += 1
        if k >= max_ins:
            break
