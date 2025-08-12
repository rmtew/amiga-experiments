#import "Basic";
#import "File";
#import "Bit_Operations";

formatHex :: #bake_arguments formatInt(base = 16);

read_u8 :: (ps: *string) -> u8 {
    assert(ps.count >= 1);
    result := << cast(*u8)ps.data;
    ps.data += 1;
    ps.count -= 1;
    return result;
}

read_be_u16 :: (ps: *string) -> u16 {
    assert(ps.count >= 2);
    result := byte_swap(<< cast(*u16)ps.data);
    ps.data += 2;
    ps.count -= 2;
    return result;
}

read_be_u32 :: (ps: *string) -> u32 {
    assert(ps.count >= 4);
    result := byte_swap(<< cast(*u32)ps.data);
    ps.data += 4;
    ps.count -= 4;
    return result;
}

read_hunk_strings :: (ps: *string) -> []string {
    lib_names: [..]string;
    hs: string;
    while hs := read_hunk_string(ps) {
        if hs.count == 0 break;
        array_add(*lib_names, hs);
    }
    return lib_names;
}

read_hunk_string :: (ps: *string) -> string {
    max_len := read_be_u32(ps) * 4;
    if max_len < 1
        return "";
   
    t: string;
    t.count = find_terminating_zero(t.data);
    t.data = ps.data;
    assert(ps.count >= max_len);
    ps.data += max_len;
    ps.count -= max_len;
    return t;
}

find_terminating_zero :: (d: *u8) -> int {
    i := 0;
    while d[i] != 0 {
        i += 1;
    }
    return i;
}

Hunk_Type :: enum u32 {
    UNIT           :: 999;
    NAME           :: 1000;
    CODE           :: 1001;
    DATA           :: 1002;
    BSS            :: 1003;
    RELOC32        :: 1004;
    RELOC16        :: 1005;
    RELOC8         :: 1006;
    EXT            :: 1007;
    SYMBOL         :: 1008;
    DEBUG          :: 1009;
    END            :: 1010;
    HEADER         :: 1011;

    BREAK          :: 1014;
    OVERLAY        :: 1013;

    DREL32         :: 1015;
    DREL16         :: 1016;
    DREL8          :: 1017;

    LIB            :: 1018;
    INDEX          :: 1019;

    RELOC32SHORT   :: 1020;
    ABSRELOC16     :: 1021;
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

Hunk_File :: struct {
    type: Hunk_Type;
    lib_names: []string;
    segment_count: u32;
    segments: []File_Segment;
    relocations: []u32;
}

File_Segment :: struct {
    type: Hunk_Type;        // Hunk type constant.
    index: u32;             // Slot index.
    offset: u32;            // Offset in file.
    size: u32;              // Size of hunk contents.
    name: string;           // Set if name hunk was present.
    memory_flags: u32;      // Amiga MEMF_ flags.
    buffer: string;         // Data or code buffer.
    relocations: []u32;     // Locations of pointers to relocate.
    symbols: [..]Symbol;    // Debug symbols for offsets.
}

Symbol :: struct {
    offset: u32;
    name: string;
}

main :: () {
    args := get_command_line_arguments();
    if args.count != 2 {
        print("Syntax: % <file>", args[0]);
        return;
    }

    file, open_success := file_open(args[1], true, true);
    if !open_success return; // Error is logged.

    len, len_success := file_length(file);
    if !len_success  return;

    file_buffer, read_success := read_entire_file(file);
    if !read_success return; // Error is logged.

    s: string;
    s.count = len;
    s.data = file_buffer.data;

    hf := read_hunk_header(*s);
    if hf.type != .HEADER {
        log("Does not have HUNK_%\n", hf.type);
        return;
    }

    for 0..hf.segment_count-1 {
        segment := *hf.segments[it];
        segment.index = it;

        hunk_raw_id := read_be_u32(*s);
        segment.type = cast(Hunk_Type)(hunk_raw_id & 0x3FFFFFFF);
        segment.memory_flags = hunk_raw_id & 0xE0000000;
        hunk_size := read_be_u32(*s) * 4;
        if segment.type == Hunk_Type.CODE || segment.type == Hunk_Type.DATA {
            segment.buffer.count = hunk_size;
            segment.buffer.data = s.data;
            s.data += hunk_size;
        } else if segment.type == Hunk_Type.BSS {
            segment.buffer.count = 0;
        } else {
            log("Unexpected segment hunk follows..\n");
        }
        log("Hunk %: % % %\n", it, segment.type, describe_amiga_memory_flags(segment.memory_flags), hunk_size);

        relocations: [..]u32;
        while next_hunk_id := cast(Hunk_Type)read_be_u32(*s) {
            if next_hunk_id == {
                case Hunk_Type.END;
                    break;
                case Hunk_Type.RELOC32; #through;
                case Hunk_Type.DREL32; #through;
                case Hunk_Type.RELOC32SHORT; #through;
                case Hunk_Type.ABSRELOC16;
                    log("  %\n", next_hunk_id);
                    relocation_count := ifx next_hunk_id == Hunk_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                    log("    Relocations: %\n", relocation_count);
                    while relocation_count > 0 {
                        target_hunk_id := ifx next_hunk_id == Hunk_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                        for 1..relocation_count {
                            relocation_offset := ifx next_hunk_id == Hunk_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                            array_add(*relocations, relocation_offset);
                        }
                        relocation_count = ifx next_hunk_id == Hunk_Type.RELOC32 read_be_u32(*s) else read_be_u16(*s);
                    }
                    alignment_fix := (s.data - file_buffer.data) & 2;
                    s.data += alignment_fix;
                    log("    Adjustment: %\n", alignment_fix);
                case Hunk_Type.SYMBOL;
                    log("  %\n", next_hunk_id);
                    symbol_name := read_hunk_string(*s);
                    while symbol_name.count > 0 {
                        symbol_value := read_be_u32(*s);
                        symbol_name = read_hunk_string(*s);
                        array_add(*segment.symbols, Symbol.{ symbol_value, symbol_name });
                    }
                    log("    Symbols: %\n", segment.symbols.count);
                case Hunk_Type.DEBUG;
                    log("  %\n", next_hunk_id);
                    skip_size := read_be_u32(*s) * 4;
                    s.data += skip_size;
                case Hunk_Type.NAME;
                    log("  %\n", next_hunk_id);
                    segment.name = read_hunk_string(*s);
            }
        }

        if relocations.count > 0 {
            segment.relocations = NewArray(relocations.count, u32, initialized = false);
            memcpy(segment.relocations.data, relocations.data, relocations.count * size_of(u32));            
            array_free(relocations);
        }
    }
}

read_hunk_header :: (ps: *string) -> Hunk_File {
    hf: Hunk_File;
    hf.type = cast(Hunk_Type)read_be_u32(ps);
    if hf.type != Hunk_Type.HEADER return hf;

    log("File hunk: %\n", hf.type);
    hf.lib_names = read_hunk_strings(ps);
    for hf.lib_names log("Lib name: %\n", it);
    hf.segment_count = read_be_u32(ps);
    log("Hunk count: %\n", hf.segment_count);
    first_hunk_slot := read_be_u32(ps);
    last_hunk_slot := read_be_u32(ps);
    log("Hunk slots: %..%\n", first_hunk_slot, last_hunk_slot);
 
    hf.segments = NewArray(hf.segment_count, File_Segment);
    for 0..hf.segment_count-1 {
        segment := *hf.segments[it];
        hunk_raw_size := read_be_u32(ps);
        segment.memory_flags = hunk_raw_size & 0xE0000000;
        segment.size = (hunk_raw_size & 0x3FFFFFFF) * 4;
        print("hunk % % % %\n", it, formatHex(hunk_raw_size), describe_amiga_memory_flags(segment.memory_flags), segment.size);
    }

    return hf;
}
