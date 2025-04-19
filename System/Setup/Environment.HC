AutoComplete(0);

#define include_noreindex #include

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

CMemBlk* ShrinkMemBlkByPags(CMemBlk* from, I64 count)
{
    from->pags -= count;
    U64 to = from;
    to += count * MEM_PAG_SIZE;
    MemCpy(to, from, MEM_PAG_SIZE);
    return to;
}

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

I64 @t(Bool _condition, I64 _true, I64 _false)
{
    if (_condition)
        return _true;
    return _false;
}

U0 @erythros_mem_task_loop()
{
    while (1) {
        Sleep(1);
    };
}

// Before doing anything else, we:

// 1. Mark memory in code heap below 0x1000000 as used.
sys_code_bp->mem_free_lst->next->pags = 0;

// 2. Free up 64MB at bottom of code heap for non-HolyC programs
sys_code_bp->mem_free_lst = ShrinkMemBlkByPags(sys_code_bp->mem_free_lst, 131072);

// 3. Enable SSE
@sse_enable;
@sse_enable_on_all_cores;

// 4. Init mem_tasks

CTask* erythros_mem_task = Spawn(&@erythros_mem_task_loop, , "ErythrosMemTask");

#define MALLOC_MEM_TASK_COUNT 4
CTask** malloc_mem_task = CAlloc(sizeof(CTask*) * MALLOC_MEM_TASK_COUNT, erythros_mem_task);
I64 malloc_current_mem_task = 0;

U0 @malloc_mem_tasks_init()
{
    U8* scratch_buffer[64];
    I64 i;
    for (i = 0; i < MALLOC_MEM_TASK_COUNT; i++) {
        StrPrint(scratch_buffer, "ErythrosMallocTask%d", i);
        malloc_mem_task[i] = Spawn(&@erythros_mem_task_loop, , scratch_buffer);
    }
}

@malloc_mem_tasks_init;

U0 dd() { DocDump(adam_task->put_doc); }
//@patch_jmp_rel32(&Fault2, &Reboot); // Reboot instead of crashing to the debugger
U0 NoBeep(I8, Bool) {};
@patch_jmp_rel32(&Beep, &NoBeep); // Don't delay on beep when entering debugger

Bool BlkDevLock2(CBlkDev* bd)
{
    BlkDevChk(bd);
    while (bd->lock_fwding)
        bd = bd->lock_fwding;
    if (!Bt(&bd->locked_flags, BDlf_LOCKED) || bd->owning_task != Fs) {
        while (LBts(&bd->locked_flags, BDlf_LOCKED))
            Sleep(Rand * 10);
        bd->owning_task = Fs;
        return TRUE;
    } else
        return FALSE;
}

Bool DrvLock2(CDrv* dv)
{
    DrvChk(dv);
    BlkDevLock2(dv->bd);
    if (!Bt(&dv->locked_flags, DVlf_LOCKED) || dv->owning_task != Fs) {
        while (LBts(&dv->locked_flags, DVlf_LOCKED))
            Sleep(Rand * 10);
        dv->owning_task = Fs;
        return TRUE;
    } else
        return FALSE;
}

CTask* SpawnQue2(U0 (*fp_addr)(U8* data), U8* data = NULL, U8* task_name = NULL,
    I64 target_cpu, CTask* parent = NULL, // NULL means adam
    I64 stk_size = 0, I64 flags = 1 << JOBf_ADD_TO_QUE)
{
    CTask* res;
    CJob* tmpc = JobQue(fp_addr, data, target_cpu,
        flags, JOBT_SPAWN_TASK, task_name, parent, stk_size);
    CJobCtrl* ctrl;

    while (!Bt(&tmpc->flags, JOBf_DONE)) {
        LBts(&Fs->task_flags, TASKf_IDLE);
        Sleep(1);
    }
    LBtr(&Fs->task_flags, TASKf_IDLE);

    res = tmpc->spawned_task;
    ctrl = tmpc->ctrl;
    PUSHFD
    CLI while (LBts(&ctrl->flags, JOBCf_LOCKED))
        Sleep(1);
    QueRem(tmpc);
    LBtr(&ctrl->flags, JOBCf_LOCKED);
    POPFD
    JobDel(tmpc);
    return res;
}

@patch_jmp_rel32(&BlkDevLock, &BlkDevLock2); // Patch BlkDevLock so we don't deadlock on multiple tasks reading from virtio disk
@patch_jmp_rel32(&DrvLock, &DrvLock2);       // Patch DrvLock so we don't deadlock on multiple tasks reading from virtio disk
@patch_jmp_rel32(&SpawnQue, &SpawnQue2);     // Patch SpawnQue so we don't deadlock on spawning multicore tasks simultaneously
