U64 stbtt_heap = MAlloc(1048576 * 32);
U64 stbtt_pos = 0;

U64 @stbtt_malloc(I64 size)
{
    //"stbtt_malloc(%d)\n", size;
    U64 ptr = stbtt_heap + stbtt_pos;
    stbtt_pos += size;
    return ptr;
}

U0 @stbtt_free(U8* ptr)
{
    no_warn ptr;
    //"stbtt_free(0x%08x)\n", ptr;
}

U0 _Z15truetype_malloci()
{
    PUSH_SYSV_REGS
    GET_SYSV_ARGS
    @stbtt_malloc(p0);
    POP_SYSV_REGS
}

U0 _Z13truetype_freePv()
{
    PUSH_SYSV_REGS
    GET_SYSV_ARGS
    @stbtt_free(p0);
    POP_SYSV_REGS
}
