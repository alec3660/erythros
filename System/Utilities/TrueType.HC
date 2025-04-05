Silent(1); // This is needed to suppress "Function should return val" warnings for wrappers to non-HolyC functions

class stbtt__buf {
    U8* data;
    I32 cursor;
    I32 size;
};

class stbtt_fontinfo {
    U8* userdata;
    U8* data;                                          // pointer to .ttf file
    I32 fontstart;                                     // offset of start of font
    I32 numGlyphs;                                     // number of glyphs, needed for range checking
    I32 loca, head, glyf, hhea, hmtx, kern, gpos, svg; // table locations as offset from start of .ttf
    I32 index_map;                                     // a cmap mapping for our chosen character encoding
    I32 indexToLocFormat;                              // format needed to map from glyph index to glyph

    stbtt__buf cff;         // cff font data
    stbtt__buf charstrings; // the charstring index
    stbtt__buf gsubrs;      // global charstring subroutines index
    stbtt__buf subrs;       // private charstring subroutines index
    stbtt__buf fontdicts;   // array of font dicts
    stbtt__buf fdselect;    // map from glyph to fontdict
};

I32 @stbtt_InitFont(stbtt_fontinfo* info, U8* data, I32 offset)
{
    U64 reg RDI rdi = info;
    U64 reg RSI rsi = data;
    U64 reg RDX rdx = offset;
    no_warn rdi, rsi, rdx;
    asm {
        MOV RAX, STBTT_INITFONT
        CALL RAX
    }
}

U8* @stbtt_RenderText(stbtt_fontinfo* info, I32 b_w, I32 b_h, I32 l_h, U8* word)
{
    U64 reg RDI rdi = info;
    U64 reg RSI rsi = b_w;
    U64 reg RDX rdx = b_h;
    U64 reg RCX rcx = l_h;
    U64 reg R8 r8 = word;
    no_warn rdi, rsi, rdx, rcx, r8;
    asm {
        MOV RAX, STBTT_RENDERTEXT
        CALL RAX
    }
}

U8* @stbtt_GetFontNameDefault(stbtt_fontinfo* font, I32* length)
{
    U64 reg RDI rdi = font;
    U64 reg RSI rsi = length;
    no_warn rdi, rsi;
    asm {
        MOV RAX, STBTT_GETFONTNAMEDEFAULT
        CALL RAX
    }
}

Silent(0);

"truetype ";
