/*
Copyright 2025 Richard Tew. All rights reserved. No license granted for use or modification.
*/

read_hunk_string_raw :: (ps: *string, max_len: u32) -> string {
    t: string;
    assert(ps.count >= max_len);
    i := 0;
    while t.data[i] != 0 && i < max_len i += 1;
    t.count = i; // <= max_len
    t.data = ps.data;
    ps.data += max_len;
    ps.count -= max_len;
    return t;
}

read_hunk_string :: (ps: *string) -> string {
    max_len := read_be_u32(ps) * 4;
    if max_len < 1
        return "";
   
    return read_hunk_string_raw(ps, max_len);
}

Amiga_Segment_Type :: enum u32 {
    NULL            :: 0;

    UNIT            :: 999;
    NAME            :: 1000;
    CODE            :: 1001;
    DATA            :: 1002;
    BSS             :: 1003;
    RELOC32         :: 1004;
    RELOC16         :: 1005;
    RELOC8          :: 1006;
    EXT             :: 1007;
    SYMBOL          :: 1008;
    DEBUG           :: 1009;
    END             :: 1010;
    HEADER          :: 1011;

    BREAK           :: 1014;
    OVERLAY         :: 1013;

    DREL32          :: 1015;
    DREL16          :: 1016;
    DREL8           :: 1017;

    LIB             :: 1018;
    INDEX           :: 1019;

    RELOC32SHORT    :: 1020;
    ABSRELOC16      :: 1021;
}

MEMF_CHIP   :: 0x40000000;
MEMF_FAST   :: 0x80000000;
MEMF_PUBLIC :: 0x00000000;
MEMF_LOCAL  :: 0x10000000; // Non-initialized memory (BSS hunk, cleared to zero).
MEMF_CLEAR  :: 0x10000000; // Alias for MEMF_LOCAL, used for BSS hunks.

describe_amiga_memory_flags :: (memory_flags: u32) -> string {
    names: [..]string;
    if memory_flags & MEMF_CHIP array_add(*names, "MEMF_CHIP");
    if memory_flags & MEMF_FAST array_add(*names, "MEMF_FAST");
    if memory_flags & MEMF_LOCAL array_add(*names, "MEMF_CLEAR");

    if names.count == 0 return "MEMF_PUBLIC";

    builder: String_Builder;
    init_string_builder(*builder);
    for names {
        if it_index > 0 append(*builder, "|");
        append(*builder, it);
    }
    return builder_to_string(*builder);
}

parse_amiga_executable_file :: (file_buffer: string) -> *Executable_File {
    s: string;
    s.count = file_buffer.count;
    s.data = file_buffer.data;

    leading_type := cast(Amiga_Segment_Type)read_be_u32(*s);
    if leading_type != Amiga_Segment_Type.HEADER {
        log("Expected HUNK_%, got HUNK_%\n", Amiga_Segment_Type.HEADER, leading_type, user_flags=LOG_DEBUG);
        return null;
    }

    hf := New(Executable_File);
    hf.type = leading_type;
    hf.file_arch = File_Arch.AMIGA_M68K;
    hf.file_buffer = file_buffer;

    log("File hunk: %\n", hf.type, user_flags=LOG_DEBUG);
    hf.lib_names = read_hunk_strings(*s);
    for hf.lib_names log("Lib name: %\n", it, user_flags=LOG_DEBUG);
    hf.segment_count = read_be_u32(*s);
    log("Hunk count: %\n", hf.segment_count, user_flags=LOG_DEBUG);
    /* If no resident libraries are referenced this will be zero. Otherwise this will be the number
       of hunks in resident libraries and the loader opens the library and copies these entries
       from its hunk table. If this is overlay related there will also be pre-existing entries. */
    first_hunk_slot := read_be_u32(*s);
    last_hunk_slot := read_be_u32(*s);
    log("Hunk slots: %..%\n", first_hunk_slot, last_hunk_slot, user_flags=LOG_DEBUG);

    assert(last_hunk_slot - first_hunk_slot + 1 == hf.segment_count);
    hf.segments = NewArray(hf.segment_count, File_Segment);
    for 0..hf.segment_count-1 {
        segment := *hf.segments[it];
        segment.index = it;
        hunk_raw_size := read_be_u32(*s);
        segment.memory_flags = hunk_raw_size & 0xE0000000;
        segment.size = (hunk_raw_size & 0x3FFFFFFF) * 4;
        log("hunk % % % %\n", it, formatHex(hunk_raw_size),
            describe_amiga_memory_flags(segment.memory_flags), segment.size, user_flags=LOG_DEBUG);
    }

    for 0..hf.segment_count-1 {
        segment := *hf.segments[it];
        assert(segment.index == it);

        hunk_raw_id := read_be_u32(*s);
        segment.type = cast(Amiga_Segment_Type)(hunk_raw_id & 0x3FFFFFFF);
        segment.memory_flags = hunk_raw_id & 0xE0000000;
        segment.data_size = read_be_u32(*s) * 4;
        if segment.type == Amiga_Segment_Type.CODE || segment.type == Amiga_Segment_Type.DATA {
            segment.buffer.count = segment.data_size;
            segment.buffer.data = s.data;
            s.data += segment.data_size;
        } else if segment.type == Amiga_Segment_Type.BSS {
            // This is the space of the hunk size we just read, zeroed.
            segment.buffer.count = 0;
        } else {
            log("Unexpected segment hunk follows..\n", user_flags=LOG_DEBUG);
        }
        log("Hunk %: % % %\n", it, segment.type, describe_amiga_memory_flags(segment.memory_flags),
            segment.data_size, user_flags=LOG_DEBUG);

        relocations: [..]u32;
        while next_hunk_id := cast(Amiga_Segment_Type)read_be_u32(*s) {
            if next_hunk_id == {
                case Amiga_Segment_Type.END;
                    break;
                case Amiga_Segment_Type.RELOC32; #through;
                case Amiga_Segment_Type.DREL32; #through;
                case Amiga_Segment_Type.RELOC32SHORT; #through;
                case Amiga_Segment_Type.ABSRELOC16;
                    log("  %\n", next_hunk_id, user_flags=LOG_DEBUG);
                    relocation_count := ifx next_hunk_id == Amiga_Segment_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                    log("    Relocations: %\n", relocation_count, user_flags=LOG_DEBUG);
                    while (relocation_count) > 0 {
                        target_hunk_id := ifx next_hunk_id == Amiga_Segment_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                        for 1..relocation_count {
                            relocation_offset := ifx next_hunk_id == Amiga_Segment_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                            array_add(*relocations, relocation_offset);
                        }
                        relocation_count = ifx next_hunk_id == Amiga_Segment_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                    }
                    alignment_fix := (s.data - file_buffer.data) & 2;
                    s.data += alignment_fix;
                    log("    Adjustment: %\n", alignment_fix, user_flags=LOG_DEBUG);
                case Amiga_Segment_Type.SYMBOL;
                    log("  %\n", next_hunk_id, user_flags=LOG_DEBUG);
                    while 1 {
                        raw_symbol_len := read_be_u32(*s) * 4;
                        if !raw_symbol_len break;
                        symbol_type := raw_symbol_len & 0xFF000000;
                        symbol_name := read_hunk_string_raw(*s, raw_symbol_len & 0x00FFFFFF);
                        symbol_value := read_be_u32(*s);
                        array_add(*segment.symbols, Symbol.{ symbol_type, symbol_value, symbol_name });
                    }
                    log("    Symbols: %\n", segment.symbols.count, user_flags=LOG_DEBUG);
                case Amiga_Segment_Type.DEBUG;
                    log("  %\n", next_hunk_id, user_flags=LOG_DEBUG);
                    segment.debug_data.count = read_be_u32(*s) * 4;
                    segment.debug_data.data = s.data;
                    s.data += segment.debug_data.count;
                case Amiga_Segment_Type.NAME;
                    log("  %\n", next_hunk_id, user_flags=LOG_DEBUG);
                    // The linker combines hunks that share a name (UNIT).
                    segment.name = read_hunk_string(*s);
            }
        }

        if relocations.count > 0 {
            segment.relocations = NewArray(relocations.count, u32, initialized = false);
            memcpy(segment.relocations.data, relocations.data, relocations.count * size_of(u32));            
            array_free(relocations);
        }
    }
    return hf;
}
