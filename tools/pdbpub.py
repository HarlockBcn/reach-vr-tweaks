# Dumps the public symbols (S_PUB32) of a PDB (MSF 7.0) as "rva<TAB>flags<TAB>name",
# using the PE section table to translate seg:off -> RVA.
# usage: pdbpub.py Atlas-Win64-Shipping.pdb Atlas-Win64-Shipping.exe publics.txt
import struct, sys, mmap

pdb_path, exe_path, out_path = sys.argv[1], sys.argv[2], sys.argv[3]

f = open(pdb_path, 'rb')
m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
magic = b"Microsoft C/C++ MSF 7.00\r\n\x1aDS\0\0\0"
assert m[:len(magic)] == magic
block_size, free_map, num_blocks, dir_bytes, _unk, block_map_addr = struct.unpack_from('<6I', m, 32)

def blocks_data(block_list, size):
    out = bytearray()
    for b in block_list:
        out += m[b * block_size:(b + 1) * block_size]
    return bytes(out[:size])

n_dir_blocks = (dir_bytes + block_size - 1) // block_size
dir_block_ids = struct.unpack_from('<%dI' % n_dir_blocks, m, block_map_addr * block_size)
directory = blocks_data(dir_block_ids, dir_bytes)
num_streams = struct.unpack_from('<I', directory, 0)[0]
sizes = struct.unpack_from('<%dI' % num_streams, directory, 4)
pos = 4 + 4 * num_streams
stream_blocks = []
for s in sizes:
    if s == 0xFFFFFFFF:
        s = 0
    n = (s + block_size - 1) // block_size
    stream_blocks.append(struct.unpack_from('<%dI' % n, directory, pos))
    pos += 4 * n

def stream(i):
    s = sizes[i]
    return blocks_data(stream_blocks[i], 0 if s == 0xFFFFFFFF else s)

dbi = stream(3)
# DBI header: ... SymRecordStream at offset 20 (uint16)
sym_rec_stream = struct.unpack_from('<H', dbi, 20)[0]
syms = stream(sym_rec_stream)

# PE sections
pe = open(exe_path, 'rb').read(4096)
e_lfanew = struct.unpack_from('<I', pe, 0x3C)[0]
nsec = struct.unpack_from('<H', pe, e_lfanew + 6)[0]
opt_size = struct.unpack_from('<H', pe, e_lfanew + 20)[0]
sec_off = e_lfanew + 24 + opt_size
sections = []
for i in range(nsec):
    va = struct.unpack_from('<I', pe, sec_off + i * 40 + 12)[0]
    sections.append(va)

out = open(out_path, 'w', encoding='utf-8')
p = 0
count = 0
while p + 4 <= len(syms):
    reclen, rectype = struct.unpack_from('<HH', syms, p)
    if reclen == 0:
        break
    if rectype == 0x110E:  # S_PUB32
        flags, off, seg = struct.unpack_from('<IIH', syms, p + 4)
        name_end = syms.index(b'\0', p + 14)
        name = syms[p + 14:name_end].decode('utf-8', 'replace')
        if 1 <= seg <= len(sections):
            out.write('%x\t%d\t%s\n' % (sections[seg - 1] + off, flags, name))
            count += 1
    p += reclen + 2
out.close()
print('publics:', count)
