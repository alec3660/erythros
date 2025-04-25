AutoComplete(0);

U0 @sse_enable()
{
    /* clang-format off */
    asm
    {
        MOV_EAX_CR0
        AND AX, 0xFFFB // clear coprocessor emulation CR0.EM
        OR AX, 0x2 // set coprocessor monitoring  CR0.MP
        MOV_CR0_EAX
        MOV_EAX_CR4
        OR AX, 3 << 9 // set CR4.OSFXSR and CR4.OSXMMEXCPT at the same time
        MOV_CR4_EAX
    }
    /* clang-format on */
}

U0 @sse_enable_on_all_cores()
{
    I64 i;
    for (i = 1; i < mp_cnt; i++)
        Spawn(&@sse_enable, , , i);
}

// Enable SSE
@sse_enable;
@sse_enable_on_all_cores;

U0 @patch_call_rel32(U32 from, U32 to)
{
    *(from(U8*)) = 0xE8;
    *((from + 1)(I32*)) = to - from - 5;
}

U0 @patch_jmp_rel32(U32 from, U32 to)
{
    *(from(U8*)) = 0xE9;
    *((from + 1)(I32*)) = to - from - 5;
}

I64 tos_nist_offset = 5603; // UTC -4
#define NIST_TIME_OFFSET (tos_nist_offset - local_time_offset / CDATE_FREQ)

public
I64 CDate2Unix(CDate dt)
{ // TempleOS datetime to Unix timestamp.
    return ToI64((dt - Str2Date("1/1/1970")) / CDATE_FREQ + NIST_TIME_OFFSET);
}

public
CDate Unix2CDate(I64 timestamp)
{ // Unix timestamp to TempleOS datetime.
    return (timestamp - NIST_TIME_OFFSET) * CDATE_FREQ + Str2Date("1/1/1970");
}

// FIXME: Put these in a "Builtin" library?
U0 FifoU8Cpy(CFifoU8* f, U8* s)
{
    if (!f || !s)
        return;
    while (*s)
        FifoU8Ins(f, *s++);
}
Bool KeyDown(I64 sc) return Bt(kbd.down_bitmap, sc);
I64 T(Bool _condition, I64 _true, I64 _false)
{
    if (_condition)
        return _true;
    return _false;
}

asm
    {
_MEMCPY_U16::
        PUSH    RBP
        MOV     RBP,RSP
        PUSH    RSI
        PUSH    RDI
        CLD
        MOV     RDI,U64 SF_ARG1[RBP]
        MOV     RSI,U64 SF_ARG2[RBP]
        MOV     RCX,U64 SF_ARG3[RBP]
        REP_MOVSW
        MOV     RAX,RDI
        POP     RDI
        POP     RSI
        POP     RBP
        RET1    24    
_MEMCPY_U32::
        PUSH    RBP
        MOV     RBP,RSP
        PUSH    RSI
        PUSH    RDI
        CLD
        MOV     RDI,U64 SF_ARG1[RBP]
        MOV     RSI,U64 SF_ARG2[RBP]
        MOV     RCX,U64 SF_ARG3[RBP]
        REP_MOVSD
        MOV     RAX,RDI
        POP     RDI
        POP     RSI
        POP     RBP
        RET1    24    
_MEMCPY_U64::
        PUSH    RBP
        MOV     RBP,RSP
        PUSH    RSI
        PUSH    RDI
        CLD
        MOV     RDI,U64 SF_ARG1[RBP]
        MOV     RSI,U64 SF_ARG2[RBP]
        MOV     RCX,U64 SF_ARG3[RBP]
        REP_MOVSQ
        MOV     RAX,RDI
        POP     RDI
        POP     RSI
        POP     RBP
        RET1    24
    }

public _extern _MEMCPY_U16 U16* MemCpyU16(U16* dst, U16* src, I64 cnt);
public
_extern _MEMCPY_U32 U32* MemCpyU32(U32* dst, U32* src, I64 cnt);
public
_extern _MEMCPY_U64 U64* MemCpyU64(U64* dst, U64* src, I64 cnt);

I64 @lerp(U32 val, U32 mx1, U32 mx2)
{
    F64 r = (val & mx1) / ToF64(mx1);
    return ToI64(r * mx2);
}

CMemBlk* ShrinkMemBlkByPags(CMemBlk* from, I64 count)
{
    from->pags -= count;
    U64 to = from;
    to += count * MEM_PAG_SIZE;
    MemCpy(to, from, MEM_PAG_SIZE);
    return to;
}

I64 @t(Bool _condition, I64 _true, I64 _false)
{
    if (_condition)
        return _true;
    return _false;
}

U0 dd() { DocDump(adam_task->put_doc); }

Bool FifoU8Last(CFifoU8* f, U8* _b)
{ // Peek at back of fifo and don't remove.
    PUSHFD
    CLI if (f->in_ptr == f->out_ptr)
    {
        POPFD
        return FALSE;
    }
    else
    {
        I64 last_ptr = f->in_ptr - 1;
        if (last_ptr < 0)
            last_ptr = FifoU8Cnt(f) - 1;
        *_b = f->buf[last_ptr];
        POPFD
        return TRUE;
    }
}
