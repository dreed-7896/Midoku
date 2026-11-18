import gzip, json, sys
# Minimal protobuf writer for a Tachiyomi/Mihon backup (.tachibk): Backup{1: BackupManga*, 101: BackupSource*}
def varint(n):
    n &= (1 << 64) - 1
    out = bytearray()
    while True:
        b = n & 0x7F; n >>= 7
        if n: out.append(b | 0x80)
        else: out.append(b); return bytes(out)
def key(field, wt): return varint((field << 3) | wt)
def f_varint(field, n): return key(field, 0) + varint(n)
def f_bytes(field, b): return key(field, 2) + varint(len(b)) + b
def f_str(field, s): return f_bytes(field, s.encode())
def manga(m):
    b = f_varint(1, int(m['source'])) + f_str(2, m['url']) + f_str(3, m.get('title', ''))
    if m.get('thumbnailUrl'): b += f_str(9, m['thumbnailUrl'])
    b += f_varint(100, 1 if m.get('favorite') else 0)
    return b
def source(s): return f_str(1, s['name']) + f_varint(2, int(s['id']))
spec = json.load(open(sys.argv[1]))
body = b''.join(f_bytes(1, manga(m)) for m in spec['mangas']) + b''.join(f_bytes(101, source(s)) for s in spec['sources'])
open(sys.argv[2], 'wb').write(gzip.compress(body))
print(len(spec['mangas']), 'mangas,', len(body), 'bytes')
