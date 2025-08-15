/*
Copyright 2025 Richard Tew. All rights reserved. No license granted for use or modification.

Extract parameter list e.g. 'c...' for instruction.
Filter based on condition codes ('c...' present, compare to field flags).
If unable to process all extracted parameters then error.
*/

Metadata_Flags :: enum_flags u64 {
    NONE                :: 0;

    BYTE_EXTENSION      :: 1 << 0; // Word extension, lower 8 bits.
    WORD_EXTENSION      :: 1 << 1;
    LONG_EXTENSION      :: 1 << 2;
    z_EXTENSION         :: 1 << 3; // 'z' variable sized extension.
    TWO_WORD_EXTENSION  :: 1 << 4;

    DISPLACEMENT_BWL    :: 1 << 5; // 'd'

    MEMORY              :: 1 << 20;
    REGISTER            :: 1 << 21;
    SHIFT               :: 1 << 22;
    ROTATE              :: 1 << 23;

    ARCH_030             :: 1 << 40;
}

Condition_Codes :: enum u16 {
    T   :: 0;
    F   :: 1;
    HI  :: 2;
    LS  :: 3;
    CC  :: 4;
    CS  :: 5;
    NE  :: 6;
    EQ  :: 7;
    VC  :: 8;
    VS  :: 9;
    PL  :: 10;
    MI  :: 11;
    GE  :: 12;
    LT  :: 13;
    GT  :: 14;
    LE  :: 15;
}

Condition_Code_Flags :: enum u16 {
    NONE    ::  0;
    T       ::  1 << 0;
    F       ::  1 << 1;
    HI      ::  1 << 2;
    LS      ::  1 << 3;
    CC      ::  1 << 4;
    CS      ::  1 << 5;
    NE      ::  1 << 6;
    EQ      ::  1 << 7;
    VC      ::  1 << 8;
    VS      ::  1 << 9;
    PL      ::  1 << 10;
    MI      ::  1 << 11;
    GE      ::  1 << 12;
    LT      ::  1 << 13;
    GT      ::  1 << 14;
    LE      ::  1 << 15;
}   

Instruction_Format :: struct {
    name:               string;
    bit_layout:         string;
    metadata:           Metadata_Flags;
    condition_codes:    Condition_Code_Flags;
}

Instruction_Parameter_Type :: enum u8 {
    NONE::              0;
    DISPLACEMENT::      1;
    CONDITION_CODE::    2;
}

Instruction_Parameter :: struct {
    key:        u8;
    type:       Instruction_Parameter_Type;
    value::     union {
        displacement:       string;
        condition_codes:    Condition_Code_Flags;
        //
    }
}

Instruction_Formats :: Instruction_Format.[
    .{ "ORI to CCR",    "0000000000111100",                                 .BYTE_EXTENSION,    .NONE },
    .{ "ORI to SR",     "0000000001111100",                                 .WORD_EXTENSION,    .NONE},
    .{ "ORI",           "00000000z.m..r..",                                 .z_EXTENSION,       .NONE }, // Read sized data.
    .{ "ANDI to CCR",   "0000001000111100",                                 .BYTE_EXTENSION,    .NONE },
    .{ "ANDI to SR",    "0000001001111100",                                 .WORD_EXTENSION,    .NONE }, // Read sized data.
    .{ "ANDI",          "00000010z.m..r..",                                 .z_EXTENSION,       .NONE },
    .{ "SUBI",          "00000100z.m..r..",                                 .z_EXTENSION,       .NONE}, // z = size, m = mode, r = register
    .{ "RTM",           "000001101100tr..",                                 .NONE,    .NONE }, // t = d/a, r = register
    .{ "CALLM",         "0000011011m..r..00000000v.......",                 .NONE,    .NONE }, // v = argument count
    .{ "ADDI",          "00000110z.m..r..",                                 .z_EXTENSION,    .NONE },
    .{ "CMP2",          "00000z.011m..r..tR..000000000000",                 .NONE,    .NONE }, // R = register
    .{ "CHK2",          "00000z.011m..r..tR..100000000000",                 .NONE, .NONE },
    .{ "EORI to CCR",   "0000101000111100",                                 .BYTE_EXTENSION, .NONE },
    .{ "EORI to SR",    "0000101001111100",                                 .WORD_EXTENSION, .NONE },
    .{ "EORI",          "00001010z.m..r..",                                 .z_EXTENSION, .NONE },
    .{ "CMPI",          "00001100z.m..r..",                                 .z_EXTENSION, .NONE },
    .{ "BTST",          "0000100000m..r..00000000........",                 .NONE, .NONE }, // v = bit number
    .{ "BCHG",          "0000100001m..r..00000000........",                 .NONE, .NONE },
    .{ "BCLR",          "0000100010m..r..00000000........",                 .NONE, .NONE },
    .{ "BSET",          "0000100011m..r..00000000........",                 .NONE, .NONE },
    .{ "MOVES",         "00001110z.m..r..tR..d00000000000",                 .NONE, .NONE },
    .{ "CAS2",          "00001z.011111100dR..000D..000C..dR..000D..000C..", .NONE, .NONE },
    .{ "CAS",           "00001z.011m..r..0000000D..000C..",                 .NONE, .NONE },
    .{ "BTST",          "0000r..100m..r..",                                 .NONE, .NONE },
    .{ "BCHG",          "0000r..101m..r..",                                 .NONE, .NONE },
    .{ "BCLR",          "0000r..110m..r..",                                 .NONE, .NONE },
    .{ "BSET",          "0000r..111m..r..",                                 .NONE, .NONE },
    .{ "MOVEP",         "0000d..o..001aaa",                                 .WORD_EXTENSION, .NONE },
    .{ "MOVEA",         "00z.d..001m..r..",                                 .NONE, .NONE },
    .{ "MOVE",          "00z.r..m..m..r..",                                 .NONE, .NONE },
    .{ "MOVE from SR",  "0100000011m..r..",                                 .NONE, .NONE },
    .{ "MOVE from CCR", "0100001011m..r..",                                 .NONE, .NONE },
    .{ "NEGX",          "01000000z.m..r..",                                 .NONE, .NONE },
    .{ "CLR",           "01000010z.m..r..",                                 .NONE, .NONE },
    .{ "MOVE to CCR",   "0100010011m..r..",                                 .NONE, .NONE },
    .{ "NEG",           "01000100z.m..r..",                                 .NONE, .NONE },
    .{ "NOT",           "01000110z.m..r..",                                 .NONE, .NONE },
    .{ "MOVE to SR",    "0100011011m..r..",                                 .NONE, .NONE },
    .{ "EXT,EXTB",      "0100100o..000r..",                                 .NONE, .NONE },
    .{ "LINK",          "0100100000001r..HHHHHHHHHHHHHHHHLLLLLLLLLLLLLLLL", .NONE, .NONE },
    .{ "NBCD",          "0100100000m..r..",                                 .NONE, .NONE },
    .{ "SWAP",          "0100100001000r..",                                 .NONE, .NONE },
    .{ "BKPT",          "0100100001001V..",                                 .NONE, .NONE },
    .{ "PEA",           "0100100001m..r..",                                 .NONE, .NONE },
    .{ "BGND",          "0100101011111010",                                 .NONE, .NONE },
    .{ "ILLEGAL",       "0100101011111100",                                 .NONE, .NONE },
    .{ "TAS",           "0100101011m..r..",                                 .NONE, .NONE },
    .{ "TST",           "01001010z.m..r..",                                 .NONE, .NONE },
    .{ "MULU.l",        "0100110000m..r..0D..0z0000000r..",                 .NONE, .NONE },
    .{ "MULS.l",        "0100110000m..r..0D..1z0000000r..",                 .NONE, .NONE },
    .{ "DIVU.l",        "0100110001m..r..0D..0z0000000r..",                 .NONE, .NONE },
    .{ "DIVS.l",        "0100110001m..r..0D..1z0000000r..",                 .NONE, .NONE },
    .{ "TRAP",          "010011100100v...",                                 .NONE, .NONE },
    .{ "LINK",          "0100111001010r..",                                 .WORD_EXTENSION, .NONE },
    .{ "UNLK",          "0100111001011r..",                                 .NONE, .NONE },
    .{ "MOVE USP",      "010011100110dr..",                                 .NONE, .NONE },
    .{ "RESET",         "0100111001110000",                                 .NONE, .NONE },
    .{ "NOP",           "0100111001110001",                                 .NONE, .NONE },
    .{ "STOP",          "0100111001110010",                                 .WORD_EXTENSION, .NONE },
    .{ "RTE",           "0100111001110011",                                 .NONE, .NONE },
    .{ "RTD",           "0100111001110100",                                 .WORD_EXTENSION, .NONE },
    .{ "RTS",           "0100111001110101",                                 .NONE, .NONE },
    .{ "TRAPV",         "0100111001110110",                                 .NONE, .NONE },
    .{ "RTR",           "0100111001110111",                                 .NONE, .NONE },
    .{ "MOVEC",         "010011100111101Ddr..c...........",                 .NONE, .NONE },
    .{ "JSR",           "0100111010m..r..",                                 .NONE, .NONE },
    .{ "JMP",           "0100111011m..r..",                                 .NONE, .NONE },
    .{ "MOVEM",         "01001d001zm..r..l...............",                 .NONE, .NONE },
    .{ "LEA",           "0100r..111m..r..",                                 .NONE, .NONE },
    .{ "CHK",           "0100r..z.0m..r..",                                 .NONE, .NONE },
    .{ "ADDQ",          "0101d..0z.m..r..",                                 .NONE, .NONE },
    .{ "SUBQ",          "0101d..1z.m..r..",                                 .NONE, .NONE },
    .{ "DBcc",          "0101c...11001r..",                                 .NONE, .NONE },
    .{ "TRAPcc",        "0101c...11111o..",                                 .WORD_EXTENSION | .LONG_EXTENSION, .NONE },
    .{ "Scc",           "0101c...11m..r..",                                 .NONE, .NONE },
    .{ "BRA",           "01100000d.......",                                 .DISPLACEMENT_BWL, .NONE },
    .{ "BSR",           "01100001d.......",                                 .DISPLACEMENT_BWL, .NONE },
    .{ "Bcc",           "0110c...d.......",                                 .DISPLACEMENT_BWL, .CC|.CS|.EQ|.GE|.GT|.HI|.LE|.LS|.LT|.MI|.NE|.PL|.VC|.VS  },
    .{ "MOVEQ",         "0111r..0d.......",                                 .NONE, .NONE },
    .{ "DIVU,DIVUL.w",  "1000r..011m..r..",                                 .NONE, .NONE },
    .{ "SBCD",          "1000r..10000fr..",                                 .NONE, .NONE },
    .{ "PACK",          "1000r..10100fr..",                                 .NONE, .NONE },
    .{ "UNPK",          "1000r..11000fr..",                                 .WORD_EXTENSION, .NONE },
    .{ "DIVU,DIVUL.w",  "1000r..111m..r..",                                 .NONE, .NONE },
    .{ "OR",            "1000r..o..m..r..",                                 .NONE, .NONE },
    .{ "SUBX",          "1001r..1z.00fr..",                                 .NONE, .NONE },
    .{ "SUB",           "1001r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "SUBA",          "1001r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "CMPM",          "1011r..1z.001r..",                                 .NONE, .NONE },
    .{ "CMP",           "1011r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "CMPA",          "1011r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "EOR",           "1011r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "MULU.w",        "1100r..011m..r..",                                 .NONE, .NONE },
    .{ "ABCD",          "1100r..10000fr..",                                 .NONE, .NONE },
    .{ "MULS.w",        "1100r..111m..r..",                                 .NONE, .NONE },
    .{ "EXG",           "1100r..1o....r..",                                 .NONE, .NONE },
    .{ "AND",           "1100r..o..m..r..",                                 .NONE, .NONE },
    .{ "ADDX",          "1101r..1z.00fr..",                                 .NONE, .NONE },
    .{ "ADDA",          "1101r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "ADD",           "1101r..o..m..r..",                                 .NONE, .NONE }, // DUPE
    .{ "ASL,ASR",       "1110000f11m..r..",                                 .MEMORY|.SHIFT, .NONE },
    .{ "LSL,LSR",       "1110001f11m..r..",                                 .MEMORY|.SHIFT, .NONE },
    .{ "ROXL,ROXR   ",  "1110010f11m..r..",                                 .MEMORY|.ROTATE, .NONE },
    .{ "ROL,ROR",       "1110011f11m..r..",                                 .MEMORY|.ROTATE, .NONE },
    // .{ "BFTST   ",              "",                                 .NONE, .NONE },
    // .{ "BFEXTU",              "",                                 .NONE, .NONE },
    // .{ "BFCHG",              "",                                 .NONE, .NONE },
    // .{ "BFEXTS",              "",                                 .NONE, .NONE },
    // .{ "BFCLR",              "",                                 .NONE, .NONE },
    // .{ "BFFFO",              "",                                 .NONE, .NONE },
    // .{ "BFSET",              "",                                 .NONE, .NONE },
    // .{ "BFINS",              "",                                 .NONE, .NONE },
    .{ "ASL,ASR",         "1110c..fz.f00r..",                                 .REGISTER|.SHIFT, .NONE },
    .{ "LSL,LSR",         "1110c..fz.f01r..",                                 .REGISTER|.SHIFT, .NONE },
    .{ "ROXL,ROXR   ",    "1110c..fz.f10r..",                                 .REGISTER|.ROTATE, .NONE },
    .{ "ROL,ROR",         "1110c..fz.f11r..",                                 .REGISTER|.ROTATE, .NONE },
    // ... More floating point and others for other processors.
];

Format_Variable :: struct {
    char:   u8;
    index:  s64;
    count:  s64;
}

Parsed_Format :: struct {
    variables: [..]Format_Variable;
}

Parsed_Formats: [Instruction_Formats.count]Parsed_Format;

Instruction_Candidate :: struct {
    sequence:       s64;
    static_mask:    u16;
    match_word:     u16;
    format:         *Instruction_Format;
}

instruction_candidates_primed := false;
instruction_candidates: [16][..]Instruction_Candidate;

process_instruction_formats :: () {
    for instruction: Instruction_Formats {
        match: u16 = 0;
        match_bit: u16 = 0;
        mask: u16 = 0;
        mask_bit: u16 = 0;
        for 0..16-1 {
            mask <<= 1;
            match <<= 1;
            if instruction.bit_layout[it] == {
                case "1";   mask_bit = 1; match_bit = 1;
                case "0";   mask_bit = 1; match_bit = 0;
                case;       mask_bit = 0; match_bit = 0;
            }
            mask |= mask_bit;
            match |= match_bit;
        }
        array_add(*instruction_candidates[match >> 12], .{ popcount(mask), mask, match, *instruction });
    }

    // Orders candidates by most known bits first.
    for instruction_candidates bubble_sort(it, (a, b) => b.sequence - a.sequence);
    instruction_candidates_primed = true;
}

parse_bit_layout :: (s: string) -> string {
    c: u8 = 0;
    i0 := 0;
    for s {
        //print("loop % %\n", it, it_index);
        if it == "." continue;
        if c {
            print("Done % %..%\n", c, i0, it_index-i0);
            c = 0;
        }
        if it != "0" && it != "1" {
            c = it;
            i0 = it_index;
        }
    }
    if c {
        print("Done % %..%\n", c, i0, s.count-i0);
    }
    return "";
}

Condition_Code_Names := string.[
    "T", "F", "HI", "LS", "CC", "CS", "NE", "EQ", "VC", "VS", "PL", "MI", "GE", "LT", "GT", "LE"
];

Sizes := string.[
    "", "B", "L", "W"
];

decode_ea_mode :: (segment: *File_Segment, pc: s64, ea_mode: u16, ea_register: u16, size: u16) -> s64 {
    if ea_mode == 0b111 {
        abs_address: s64 = 0;
        immediate_data: u32 = 0;
        if ea_register == 0b000 {
            abs_address = cast(s64)peek_be(s16, *segment.buffer, pc);
            pc += 2;
            print("_A%", formatHex(abs_address, minimum_digits=4));
        } else if ea_register == 0b001 {
            abs_address = cast(s64)peek_be(s32, *segment.buffer, pc);
            pc += 4;
            print("_B%", formatHex(abs_address, minimum_digits=8));
        } else if ea_register == 0b100 {
            if size == 0b01 {
                immediate_data = cast(u32)(peek_be(u16, *segment.buffer, pc) & 0xFF); // ??
                pc += 2;
                print("_C%", formatHex(abs_address, minimum_digits=2));
            } else if size == 0b10 {
                immediate_data = peek_be(u32, *segment.buffer, pc);
                pc += 4;
                print("_D%", formatHex(immediate_data, minimum_digits=8));
            } else if size == 0b11 {
                immediate_data = cast(u32)peek_be(u16, *segment.buffer, pc);
                pc += 2;
                print("_E%", formatHex(immediate_data, minimum_digits=4));
            }
        }
    }
    return pc;
}

match_instructions :: (opword: u16, matches: *[..]Instruction_Candidate) {
    for instruction_candidates[opword >> 12] if opword & it.static_mask == it.match_word array_add(matches, it);
}

decode_instruction :: (segment: *File_Segment, pc0: s64) -> s64 {
    opword := peek_be_u16(*segment.buffer, pc0);
    matches: [..]Instruction_Candidate;
    match_instructions(opword, *matches);
    for matches {
        print("... MATCH: % % % %\n", format_u16_b(it.static_mask), format_u16_b(it.match_word), it.format.name, it.format.bit_layout);
        parse_bit_layout(it.format.bit_layout);
    }
    if matches.count == 0 {
        print("... NO MATCH");
        return 0xFFFFFFFF;
    }

    print("$%: b%  h%", formatHex(pc0, minimum_digits=6), format_u16_b(opword), formatHex(opword));
    pc := pc0 + 2;

    if opword == 0x0000 {
        print("  UNKNOWN");
        return 0xFFFFFFFF;
    }

    extra_len: u16 = 0;
    /* */  if opword & 0b0110_1111_0000_0000 == 0b0110_0000_0000_0000 {
        displacement := cast(s32)cast(s8)(opword & 0b0000_0000_1111_1111);
        if displacement == 0x00 {
            displacement = cast(s32)peek_be(s16, *segment.buffer, pc);
            pc = pc + 2;
            print("_%", formatHex(displacement, minimum_digits=4));
        } else if (displacement == 0xFF) {
            displacement = peek_be(s32, *segment.buffer, pc);
            pc = pc + 4;
            print("_%", formatHex(displacement, minimum_digits=8, comma_string=""));
        }
        pc = pc0 + 2 + displacement;
        print("  BRA $% ", formatHex(pc));
    } else if opword & 0b0110_0000_0000_0000 == 0b0110_000_000_0000{
        cc := opword & 0b0000_1111_0000_0000;
        displacement := cast(s16)cast(s8)(opword & 0b0000_0000_1111_1111);
        if displacement == 0 {
            displacement = peek_be(s16, *segment.buffer, pc);
            pc = pc + 2;
            print("_%", formatHex(displacement, minimum_digits=4));
        }
        print("  B% $% ; cc=b% ", Condition_Code_Names[cc], formatHex(displacement), formatInt(cc, base=2, minimum_digits=4));
    } else if opword & 0b0100_0001_1100_0000 == 0b0100_0001_1100_0000 {
        register    := (opword & 0b0000_1110_0000_0000) >> 9;
        ea_mode     := (opword & 0b0000_0000_0011_1000) >> 3;
        ea_register := (opword & 0b0000_0000_0000_0111);
        print("  LEA $% % %; TODO", register, ea_mode, ea_register);
    } else if opword & 0b1100_0001_1100_0000 == 0b0000_0000_0100_0000 {
        register    := (opword & 0b0000_1110_0000_0000) >> 9;
        ea_mode     := (opword & 0b0000_0000_0011_1000) >> 3;
        ea_register := (opword & 0b0000_0000_0000_0111);
        pc = decode_ea_mode(segment, pc, ea_mode, ea_register, 0);
        print("  MOVEA $% % %; TODO", register, ea_mode, ea_register);
    } else if opword & 0b1100_0000_0000_0000 == 0b0000_0000_0000_0000 {
        size          := (opword & 0b0011_0000_0000_0000) >> 12;
        d_ea_register := (opword & 0b0000_1110_0000_0000) >> 9;
        d_ea_mode     := (opword & 0b0000_0001_1100_0000) >> 6;
        s_ea_mode     := (opword & 0b0000_0000_0011_1000) >> 3;
        s_ea_register := (opword & 0b0000_0000_0000_0111);
        pc = decode_ea_mode(segment, pc, d_ea_mode, d_ea_register, 0);
        pc = decode_ea_mode(segment, pc, s_ea_mode, s_ea_register, size);
        print("  MOVE.%", Sizes[size]);
    } else if opword & 0b0100_1000_1000_0000 == 0b0100_1000_1000_0000 {
        direction   := (opword & 0b0000_0100_0000_0000) >> 10;
        size        := (opword & 0b0000_0000_0100_0000) >> 6;
        ea_mode     := (opword & 0b0000_0000_0011_1000) >> 3;
        ea_register := (opword & 0b0000_0000_0000_0111);
        register_list_mask := peek_be(u16, *segment.buffer, pc);
        pc += 2;
        print("_%", formatHex(register_list_mask, minimum_digits=4));
        if ea_mode == 0b111 {
            abs_address: s64 = 0;
            if ea_register == 0b000 {
                abs_address = cast(s64)peek_be(s16, *segment.buffer, pc);
                pc += 2;
                print("_%", formatHex(abs_address, minimum_digits=4));
            } else if ea_register == 0b001 {
                abs_address = cast(s64)peek_be(s32, *segment.buffer, pc);
                pc += 4;
                print("_%", formatHex(abs_address, minimum_digits=8));
            }
        }
        print("  MOVEM $% direction=% ea_mode=% ea_register=% %", direction, size, formatInt(ea_mode, base=2, minimum_digits=3), formatInt(ea_register, base=2, minimum_digits=3), format_u16_b(register_list_mask));
    } else {
        print("  UNKNOWN");
        pc = 0xFFFFFFFF;
    }
    print("\n");
    return pc;
}

disassemble_m68k :: (hf: *Executable_File, segment_index: u32) {
    if !instruction_candidates_primed process_instruction_formats();

    segment := *hf.segments[segment_index];
    assert(segment.buffer.count > 2);
    pc: s64 = 0;
    while pc != 0xFFFFFFFF {
        pc = decode_instruction(segment, pc);
    }
    // if segment.buffer.count & 2 == 0 {
    //     v = peek_be_u16(*segment.buffer, segment.buffer.count-2);
    //     print("%\n", format_u16_b(v));
    // }
}
