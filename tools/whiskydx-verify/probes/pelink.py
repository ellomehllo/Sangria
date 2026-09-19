#!/usr/bin/env python3
"""A minimal PE32+ linker for one x86-64 COFF object.

Enough to link the freestanding D3D probe programs: merges code, read-only
and writable sections, resolves AMD64 relocations against a fixed image base
(no .reloc, so DYNAMIC_BASE is off), and synthesizes an import table for every
__imp_ symbol from a symbol->DLL map. Drops debug, unwind and linker-directive
sections. Not a general linker.

usage: pelink.py in.obj out.exe entry_symbol subsystem dll:sym,sym dll:sym ...
"""
import struct
import sys

IMAGE_BASE = 0x140000000
SECT_ALIGN = 0x1000
FILE_ALIGN = 0x200


def align(value, to):
    return (value + to - 1) // to * to


def parse(obj):
    machine, nsects, _, symptr, nsyms, optsize, _ = struct.unpack_from('<HHIIIHH', obj, 0)
    assert machine == 0x8664, hex(machine)
    strtab_off = symptr + nsyms * 18
    def strtab(offset):
        end = obj.index(b'\0', strtab_off + offset)
        return obj[strtab_off + offset:end].decode()
    sections = []
    for i in range(nsects):
        off = 20 + optsize + i * 40
        raw_name = obj[off:off + 8]
        if raw_name.startswith(b'/'):
            name = strtab(int(raw_name[1:].rstrip(b'\0')))
        else:
            name = raw_name.rstrip(b'\0').decode()
        vsize, vaddr, rawsize, rawptr, relptr, _, nrel, _, chars = struct.unpack_from('<IIIIIIHHI', obj, off + 8)
        relocs = [struct.unpack_from('<IIH', obj, relptr + r * 10) for r in range(nrel)]
        data = obj[rawptr:rawptr + rawsize] if chars & 0x80 == 0 else b'\0' * rawsize
        sections.append(dict(name=name, data=bytearray(data), chars=chars, relocs=relocs, index=i + 1))
    symbols = {}
    i = 0
    while i < nsyms:
        off = symptr + i * 18
        raw = obj[off:off + 8]
        if raw[:4] == b'\0\0\0\0':
            name = strtab(struct.unpack_from('<I', raw, 4)[0])
        else:
            name = raw.rstrip(b'\0').decode()
        value, secnum, _, sclass, naux = struct.unpack_from('<IhHBB', obj, off + 8)
        symbols[i] = dict(name=name, value=value, section=secnum, sclass=sclass)
        i += 1 + naux
    return sections, symbols


def kind(section):
    name, chars = section['name'], section['chars']
    if chars & 0x800 or chars & 0x200 or name.startswith(('.debug', '.pdata', '.xdata', '.llvm')):
        return None  # LNK_REMOVE, LNK_INFO (.drectve), debug, unwind
    if chars & 0x20:
        return '.text'
    if chars & 0x80000000:
        return '.data'
    return '.rdata'


def main():
    obj_path, out_path, entry, subsystem = sys.argv[1:5]
    import_map = {}
    for spec in sys.argv[5:]:
        dll, syms = spec.split(':')
        for sym in syms.split(','):
            import_map[sym] = dll
    obj = open(obj_path, 'rb').read()
    sections, symbols = parse(obj)

    # Place input sections into output sections.
    order = ['.text', '.rdata', '.data']
    out = {name: bytearray() for name in order}
    placement = {}
    for sec in sorted(sections, key=lambda s: s['name']):
        target = kind(sec)
        if target is None:
            continue
        al = 1 << (((sec['chars'] >> 20) & 0xF) - 1) if (sec['chars'] >> 20) & 0xF else 16
        buf = out[target]
        buf.extend(b'\0' * (align(len(buf), al) - len(buf)))
        placement[sec['index']] = (target, len(buf))
        buf.extend(sec['data'])

    # Imports: every undefined __imp_X.
    imports = {}
    for sym in symbols.values():
        if sym['section'] == 0 and sym['name'].startswith('__imp_'):
            fn = sym['name'][6:]
            if fn not in import_map:
                sys.exit(f'no DLL for import {fn}')
            imports.setdefault(import_map[fn], [])
            if fn not in imports[import_map[fn]]:
                imports[import_map[fn]].append(fn)
        elif sym['section'] == 0 and sym['sclass'] == 2 and sym['name'] not in ('__ImageBase',):
            sys.exit(f'undefined symbol {sym["name"]}')

    # Lay out RVAs.
    rva = {}
    next_rva = SECT_ALIGN
    for name in order:
        rva[name] = next_rva
        next_rva = align(next_rva + max(len(out[name]), 1), SECT_ALIGN)
    idata_rva = next_rva
    dlls = list(imports)
    desc_size = (len(dlls) + 1) * 20
    cursor = desc_size
    ilt_off, iat_off, names = {}, {}, {}
    for dll in dlls:
        ilt_off[dll] = cursor
        cursor += (len(imports[dll]) + 1) * 8
    iat_start = cursor
    for dll in dlls:
        iat_off[dll] = cursor
        cursor += (len(imports[dll]) + 1) * 8
    iat_end = cursor
    hint_off = {}
    for dll in dlls:
        for fn in imports[dll]:
            hint_off[fn] = cursor
            cursor += align(2 + len(fn) + 1, 2)
    for dll in dlls:
        names[dll] = cursor
        cursor += len(dll) + 1
    idata = bytearray(cursor)
    iat_slot = {}
    for d, dll in enumerate(dlls):
        struct.pack_into('<IIIII', idata, d * 20, idata_rva + ilt_off[dll], 0, 0,
                         idata_rva + names[dll], idata_rva + iat_off[dll])
        for f, fn in enumerate(imports[dll]):
            entry_rva = idata_rva + hint_off[fn]
            struct.pack_into('<Q', idata, ilt_off[dll] + f * 8, entry_rva)
            struct.pack_into('<Q', idata, iat_off[dll] + f * 8, entry_rva)
            idata[hint_off[fn] + 2:hint_off[fn] + 2 + len(fn)] = fn.encode()
            iat_slot[fn] = IMAGE_BASE + idata_rva + iat_off[dll] + f * 8
        idata[names[dll]:names[dll] + len(dll)] = dll.encode()
    image_end = align(idata_rva + len(idata), SECT_ALIGN)

    def address(sym):
        if sym['section'] > 0:
            target, offset = placement[sym['section']]
            return IMAGE_BASE + rva[target] + offset + sym['value']
        if sym['name'].startswith('__imp_'):
            return iat_slot[sym['name'][6:]]
        if sym['name'] == '__ImageBase':
            return IMAGE_BASE
        sys.exit(f'cannot resolve {sym["name"]}')

    # Relocate.
    for sec in sections:
        if sec['index'] not in placement:
            continue
        target, base = placement[sec['index']]
        buf = out[target]
        for vaddr, symidx, rtype in sec['relocs']:
            s = address(symbols[symidx])
            pos = base + vaddr
            place = IMAGE_BASE + rva[target] + pos
            if rtype == 1:  # ADDR64
                struct.pack_into('<Q', buf, pos, struct.unpack_from('<Q', buf, pos)[0] + s)
            elif rtype == 3:  # ADDR32NB
                struct.pack_into('<I', buf, pos, struct.unpack_from('<I', buf, pos)[0] + s - IMAGE_BASE)
            elif 4 <= rtype <= 9:  # REL32, REL32_1..5
                delta = s - (place + 4 + (rtype - 4))
                value = struct.unpack_from('<i', buf, pos)[0] + delta
                assert -2**31 <= value < 2**31
                struct.pack_into('<i', buf, pos, value)
            else:
                sys.exit(f'unsupported relocation {rtype} in {sec["name"]}')

    entry_sym = next(s for s in symbols.values() if s['name'] == entry and s['section'] > 0)
    entry_rva = address(entry_sym) - IMAGE_BASE

    # Emit.
    out_sections = [('.text', out['.text'], 0x60000020), ('.rdata', out['.rdata'], 0x40000040),
                    ('.data', out['.data'], 0xC0000040), ('.idata', idata, 0xC0000040)]
    rvas = [rva['.text'], rva['.rdata'], rva['.data'], idata_rva]
    header_size = align(0x80 + 4 + 20 + 240 + 40 * len(out_sections), FILE_ALIGN)
    image = bytearray(header_size)
    image[0:2] = b'MZ'
    struct.pack_into('<I', image, 0x3C, 0x80)
    image[0x80:0x84] = b'PE\0\0'
    struct.pack_into('<HHIIIHH', image, 0x84, 0x8664, len(out_sections), 0, 0, 0, 240, 0x0023)
    opt = 0x98
    size_code = align(len(out['.text']), FILE_ALIGN)
    size_init = sum(align(len(b), FILE_ALIGN) for _, b, _ in out_sections[1:])
    struct.pack_into('<HBBIIIII', image, opt, 0x20B, 14, 0, size_code, size_init, 0, entry_rva, rva['.text'])
    struct.pack_into('<QIIHHHHHHIIIIHHQQQQII', image, opt + 24, IMAGE_BASE, SECT_ALIGN, FILE_ALIGN,
                     6, 0, 0, 0, 6, 0, 0, image_end, header_size, 0, int(subsystem), 0x8100,
                     0x100000, 0x1000, 0x100000, 0x1000, 0, 16)
    dirs = opt + 112
    struct.pack_into('<II', image, dirs + 1 * 8, idata_rva, desc_size)
    struct.pack_into('<II', image, dirs + 12 * 8, idata_rva + iat_start, iat_end - iat_start)
    file_off = header_size
    for i, ((name, data, chars), sec_rva) in enumerate(zip(out_sections, rvas)):
        raw = align(len(data), FILE_ALIGN)
        struct.pack_into('<8sIIIIIIHHI', image, 0x98 + 240 + i * 40, name.encode(), max(len(data), 1),
                         sec_rva, raw, file_off if raw else 0, 0, 0, 0, 0, chars)
        file_off += raw
    for _, data, _ in out_sections:
        image.extend(data)
        image.extend(b'\0' * (align(len(data), FILE_ALIGN) - len(data)))
    open(out_path, 'wb').write(image)
    print(f'{out_path}: {len(image)} bytes, entry rva {entry_rva:#x}, imports ' +
          ', '.join(f'{d}({len(f)})' for d, f in imports.items()))


main()
