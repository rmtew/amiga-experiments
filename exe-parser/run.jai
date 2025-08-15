/*
Copyright 2025 Richard Tew. All rights reserved. No license granted for use or modification.
*/

#import "Basic";
#import "File";
#import "Sort";
#import "Bit_Operations";

#load "os_amiga.jai";
#load "arch_m68k.jai";

formatHex :: #bake_arguments formatInt(base = 16);
format_u16_b :: #bake_arguments formatInt(base = 2, digits_per_comma=4, comma_string="_", minimum_digits=16);
LOG_DEBUG :: 1;

peek_u8 :: (ps: *string, i: s64) -> u8 {
    assert(i<ps.count);
    return << cast(*u8)(ps.data+i);
}

read_u8 :: (ps: *string) -> u8 {
    assert(ps.count >= 1);
    result := << cast(*u8)ps.data;
    ps.data += 1;
    ps.count -= 1;
    return result;
}

peek_be :: ($T: Type, ps: *string, i: s64) -> T {
    assert(i<ps.count);
    return cast(T)byte_swap(<< cast(*T)(ps.data+i));
}

read_be :: ($T: Type, ps: *string) -> T {
    assert(ps.count >= size_of(T));
    result := byte_swap(<< cast(*T)ps.data);
    ps.data += size_of(T);
    ps.count -= size_of(T);
    return result;
}

peek_be_u16 :: (ps: *string, i: s64) -> u16 {
    assert(i<ps.count);
    return byte_swap(<< cast(*u16)(ps.data+i));
}

read_be_u16 :: (ps: *string) -> u16 {
    assert(ps.count >= 2);
    result := byte_swap(<< cast(*u16)ps.data);
    ps.data += 2;
    ps.count -= 2;
    return result;
}

peek_be_u32 :: (ps: *string, i: s64) -> u32 {
    assert(i<ps.count);
    return byte_swap(<< cast(*u32)(ps.data+i));
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

File_Arch :: enum u32 {
    UNKNOWN         :: 0;

    AMIGA_M68K      :: 1;
}

Executable_File :: struct {
    file_arch := File_Arch.UNKNOWN;
    file_buffer: string;        // The contents of the file.
    type: Amiga_Segment_Type;
    lib_names: []string;
    segment_count: u32;
    segments: []File_Segment;
    relocations: []u32;
}

File_Segment :: struct {
    type: Amiga_Segment_Type;   // Hunk type constant.
    index: u32;                 // Slot index.
    offset: u32;                // Offset in file.
    size: u32;                  // Size of hunk from leading hunk table.
    data_size: u32;             // Size of actual hunk data. Will be in buffer unless BSS.
    name: string;               // Set if name hunk was present.
    memory_flags: u32;          // Amiga MEMF_ flags.
    buffer: string;             // Data or code buffer.
    relocations: []u32;         // Locations of pointers to relocate.
    symbols: [..]Symbol;        // Debug symbols for offsets.
    debug_data: string;         // Debug data buffer, if any.
}

Symbol :: struct {
    type: u32;
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
    if !open_success return; // Error is already logged.
    defer file_close(*file);

    len, len_success := file_length(file);
    if !len_success {
        print("Unable to get file length: %\n", args[1]);
        return;
    }

    file_buffer, read_success := read_entire_file(file);
    if !read_success {
        print("Unable to read file: %\n", args[1]);
        return;
    }

    hf := parse_file(file_buffer);
    if hf  {
        defer free(hf);
        if hf.file_arch == .AMIGA_M68K {
            if hf.segments.count < 1 print("No segments.\n");
            else if hf.segments[0].type != .CODE print("First segment is not code.\n");
            else disassemble_m68k(hf, 0);
        } else
            print("Unexpected architecture: %\n", hf.file_arch);
    } else {
        print("Unable to parse file: %\n", args[1]);
    }
}

parse_file :: (file_buffer: string) -> *Executable_File {
    ahf := parse_amiga_executable_file(file_buffer);
    if ahf return ahf;
    return null;
}
