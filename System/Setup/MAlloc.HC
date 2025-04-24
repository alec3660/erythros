#define RMALLOC_REQUEST_PTR 0x280000

#define RMALLOC_BUSY_WAIT 5
#define RMALLOC_TASK_CPU 5
#define RMALLOC_TIMEOUT 1024
#define RMALLOC_TYPE_MALLOC 0
#define RMALLOC_TYPE_CALLOC 1
#define RMALLOC_TYPE_FREE 2

asm {
    //************************************
    // See ::/Doc/Credits.DD.
_RMALLOC::
        // Throws 'OutMem'
        PUSH    RBP
        MOV     RBP,RSP
        PUSH    RSI
        PUSH    RDI

        XOR     RBX,RBX
        MOV     RDX,U64 SF_ARG2[RBP]
        TEST    RDX,RDX
        JNZ     @@05
        MOV     RDX,U64 FS:CTask.addr[RBX]
@@05:   CMP     U32 CTask.task_signature[RDX],TASK_SIGNATURE_VAL

#assert CTask.task_signature == CHeapCtrl.hc_signature // location signature same

        JNE     @@10
        MOV     RDX,U64 CTask.data_heap[RDX]
@@10:   CMP     U32 CHeapCtrl.hc_signature[RDX],HEAP_CTRL_SIGNATURE_VAL
        JE      @@15
        PUSH    RDX
        CALL    &SysBadMAlloc
        JMP     I32 _SYS_HLT

@@15:   MOV     RAX,U64 SF_ARG1[RBP]
        PUSHFD
        ADD     RAX,CMemUsed.start+7 // round-up to I64
        AND     AL,0xF8
#assert CMemUsed.start >= sizeof(CMemUnused)
        CMP     RAX,CMemUsed.start
        JAE     @@20
        MOV     RAX,CMemUsed.start
@@20:

        CLI
@@25:   LOCK
        BTS     U32 CHeapCtrl.locked_flags[RDX],HClf_LOCKED
        PAUSE                                                // don't know if this inst helps
        JC      @@25

        CMP     RAX,MEM_HEAP_HASH_SIZE
        JAE     @@30
        MOV     RSI,U64 CHeapCtrl.heap_hash[RAX+RDX]
        TEST    RSI,RSI
        JZ      @@35
        MOV     RCX,U64 CMemUnused.next[RSI]
        MOV     U64 CHeapCtrl.heap_hash[RAX+RDX],RCX
        JMP     I32 RMALLOC_ALMOST_DONE

    // Big allocation
@@30:   ADD     RAX,sizeof(CMemBlk)+MEM_PAG_SIZE-1
        SHR     RAX,MEM_PAG_BITS

        PUSH    RDX // preserve HeapCtrl
        PUSH    RDX
        PUSH    RAX
        CALL    &MemPagTaskAlloc
        POP     RDX
        TEST    RAX,RAX
        JZ      @@45 // Out of memory
        MOV     RSI,RAX
        MOV     EAX,U32 CMemBlk.pags[RSI]

        SHL     RAX,MEM_PAG_BITS
        SUB     RAX,sizeof(CMemBlk)
        ADD     RSI,sizeof(CMemBlk)
        JMP     I32 RMALLOC_ALMOST_DONE

    // Little allocation, chunk-off piece from free lst chunks
@@35:   LEA     RSI,U64 CHeapCtrl.malloc_free_lst-CMemUnused.next[RDX]

@@40:   MOV     RBX,RSI
        MOV     RSI,U64 CMemUnused.next[RBX]
        TEST    RSI,RSI
        JNZ     I32 @@60
        PUSH    RAX //-**** save byte size
        ADD     RAX,16*MEM_PAG_SIZE-1
        SHR     RAX,MEM_PAG_BITS

        PUSH    RDX // preserve HeapCtrl
        PUSH    RDX
        PUSH    RAX
        CALL    &MemPagTaskAlloc
        POP     RDX
        TEST    RAX,RAX
        JNZ     @@50

    // Out of memory
@@45:   LOCK
        BTR     U32 CHeapCtrl.locked_flags[RDX],HClf_LOCKED
        POPFD
        PUSH    TRUE
        MOV     RAX,'OutMem'
        PUSH    RAX
        CALL    I32 &throw
        JMP     I32 RMALLOC_FINAL_EXIT // Never gets here, hopefully.

@@50:   MOV     RSI,RAX
        MOV     EAX,U32 CMemBlk.pags[RSI]
        SHL     RAX,MEM_PAG_BITS

                                                         // Can it be combined with last chunk? (Never Free these chunks.)
        MOV     RDI,U64 CHeapCtrl.last_mergable[RDX]
        LEA     RBX,U64 [RSI+RAX]
        CMP     RDI,RBX
        JNE     @@55

        PUSH    RAX
        MOV     EAX,U32 CMemBlk.pags[RDI]
        ADD     U32 CMemBlk.pags[RSI],EAX
                                                    // QueRem
        MOV     RAX,U64 CMemBlk.next[RDI]
        MOV     RBX,U64 CMemBlk.last[RDI]
        MOV     U64 CMemBlk.last[RAX],RBX
        MOV     U64 CMemBlk.next[RBX],RAX
        POP     RAX

@@55:   MOV     U64 CHeapCtrl.last_mergable[RDX],RSI
        LEA     RSI,U64 sizeof(CMemBlk)[RSI]
        SUB     RAX,sizeof(CMemBlk)
        LEA     RBX,U64 CHeapCtrl.malloc_free_lst-CMemUnused.next[RDX]
        MOV     RDI,U64 CMemUnused.next[RBX]
        MOV     U64 CMemUnused.next[RSI],RDI
        MOV     U64 CMemUnused.size[RSI],RAX
        MOV     U64 CMemUnused.next[RBX],RSI
        POP     RAX //+****
        JMP     @@70
@@60:   CMP     U64 CMemUnused.size[RSI],RAX
        JB      I32 @@40
        JNE     @@70

@@65:   MOV     RDI,U64 CMemUnused.next[RSI]
        MOV     U64 CMemUnused.next[RBX],RDI
        JMP     RMALLOC_ALMOST_DONE

@@70:   SUB     U64 CMemUnused.size[RSI],RAX // UPDATE FREE ENTRY
        CMP     U64 CMemUnused.size[RSI],sizeof(CMemUnused)
        JAE     @@75 // take from top of block
        ADD     U64 CMemUnused.size[RSI],RAX // doesn't fit, undo
        JMP     I32 @@40

@@75:   ADD     RSI,U64 CMemUnused.size[RSI]

RMALLOC_ALMOST_DONE:
    // RSI=res-CMemUsed.size
    // RAX=size+CMemUsed.size
    // RDX=HeapCtrl
        ADD     U64 CHeapCtrl.used_u8s[RDX],RAX

#if _CFG_HEAP_DBG
                                      // QueIns
        MOV     RDI,U64 CHeapCtrl.last_um[RDX]
        MOV     U64 CMemUsed.next[RDI],RSI
        MOV     U64 CHeapCtrl.last_um[RDX],RSI
        MOV     U64 CMemUsed.last[RSI],RDI
        LEA     RDI,U64 CHeapCtrl.next_um-CMemUsed.next[RDX]
        MOV     U64 CMemUsed.next[RSI],RDI

                                                                                                                                                                                                // Caller1/Caller2
        PUSH    RDX
        MOV     RDX,U64 [MEM_HEAP_LIMIT]
        MOV     RDI,U64 SF_RIP[RBP]
        CMP     RDI,RDX
        JB      @@80
        XOR     RDI,RDI
        MOV     U64 CMemUsed.caller1[RSI],RDI
        JMP     @@90
@@80:   MOV     U64 CMemUsed.caller1[RSI],RDI
        MOV     RDI,U64 SF_RBP[RBP]
        CMP     RDI,RDX
        JB      @@85
        XOR     RDI,RDI
        JMP     @@90
@@85:   MOV     RDI,U64 SF_RIP[RDI]
        CMP     RDI,RDX
        JB      @@90
        XOR     RDI,RDI
@@90:   MOV     U64 CMemUsed.caller2[RSI],RDI
        POP     RDX

#endif
        LOCK
        BTR     U32 CHeapCtrl.locked_flags[RDX],HClf_LOCKED
        POPFD

        MOV     U64 CMemUsed.size[RSI],RAX
        MOV     U64 CMemUsed.hc[RSI],RDX
        LEA     RAX,U64 CMemUsed.start[RSI]

        TEST    U8 [SYS_SEMAS+SEMA_HEAPLOG_ACTIVE*DFT_CACHE_LINE_WIDTH],1
        JZ      @@105
        PUSH    RAX
        PUSH    RAX
        MOV     RAX,U64 [SYS_EXTERN_TABLE]
        MOV     RAX,U64 EXT_HEAPLOG_MALLOC*8[RAX]
        TEST    RAX,RAX
        JZ      @@95
        CALL    RAX
        JMP     @@100
@@95:   ADD     RSP,8
@@100:  POP     RAX

@@105:  TEST    U8 [SYS_HEAP_INIT_FLAG],1
        JZ      RMALLOC_FINAL_EXIT

        PUSH    RAX
        MOV     RCX,U64 CMemUsed.size-CMemUsed.start[RAX]
        SUB     RCX,CMemUsed.start
        MOV     RDI,RAX
        MOV     AL,U8 [SYS_HEAP_INIT_VAL]
        REP_STOSB
        POP     RAX

RMALLOC_FINAL_EXIT:
        POP     RDI
        POP     RSI
        POP     RBP
        RET1    16
    //************************************
_RFREE::
        // Be aware of heap_hash in MemPagTaskAlloc().
        PUSH    RBP
        MOV     RBP,RSP
        PUSH    RSI
        PUSH    RDI

        TEST    U8 [SYS_SEMAS+SEMA_HEAPLOG_ACTIVE*DFT_CACHE_LINE_WIDTH],1
        JZ      @@15
        MOV     RBX,U64 SF_ARG1[RBP]
        TEST    RBX,RBX
        JZ      @@05
        MOV     RAX,U64 CMemUsed.size-CMemUsed.start[RBX]
        TEST    RAX,RAX
        JGE     @@05 // Aligned alloced chunks have neg size
        ADD     RBX,RAX
@@05:   PUSH    RBX
        MOV     RAX,U64 [SYS_EXTERN_TABLE]
        MOV     RAX,U64 EXT_HEAPLOG_FREE*8[RAX]
        TEST    RAX,RAX
        JZ      @@10
        CALL    RAX
        JMP     @@15
@@10:   ADD     RSP,8

@@15:   MOV     RSI,U64 SF_ARG1[RBP]
        TEST    RSI,RSI

#if _CFG_HEAP_DBG
        JZ      I32 RFREE_DONE
#else
        JZ      RFREE_DONE
#endif

        MOV     RAX,U64 CMemUsed.size-CMemUsed.start[RSI]
        TEST    RAX,RAX
        JGE     @@20 // Aligned alloced chunks have neg size.
                                                           // The neg size is offset to start of CMemUsed struct.
        ADD     RSI,RAX

@@20:   PUSHFD
        SUB     RSI,CMemUsed.start
        MOV     RDX,U64 CMemUsed.hc[RSI]
        CMP     U32 CHeapCtrl.hc_signature[RDX],HEAP_CTRL_SIGNATURE_VAL
        JE      @@25
        ADD     RSI,CMemUsed.start
        PUSH    RSI
        CALL    &SysBadFree
        JMP     I32 _SYS_HLT

@@25:   MOV     RAX,U64 CMemUsed.size[RSI]
        SUB     U64 CHeapCtrl.used_u8s[RDX],RAX
        CLI
@@30:   LOCK
        BTS     U32 CHeapCtrl.locked_flags[RDX],HClf_LOCKED
        PAUSE
        JC      @@30
#if _CFG_HEAP_DBG
    // QueRem
        MOV     RDX,U64 CMemUsed.next[RSI]
        MOV     RDI,U64 CMemUsed.last[RSI]
        MOV     U64 CMemUsed.last[RDX],RDI
        MOV     U64 CMemUsed.next[RDI],RDX

                                                                                                              // Caller1/Caller2
        MOV     RDX,U64 [MEM_HEAP_LIMIT]
        MOV     RDI,U64 SF_RIP[RBP]
        CMP     RDI,RDX
        JB      @@35
        XOR     RDI,RDI
        MOV     U64 CMemUnused.caller1[RSI],RDI
        JMP     @@45
@@35:   MOV     U64 CMemUnused.caller1[RSI],RDI
        MOV     RDI,U64 SF_RBP[RBP]
        CMP     RDI,RDX
        JB      @@40
        XOR     RDI,RDI
        JMP     @@45
@@40:   MOV     RDI,U64 SF_RIP[RDI]
        CMP     RDI,RDX
        JB      @@45
        XOR     RDI,RDI
@@45:   MOV     U64 CMemUnused.caller2[RSI],RDI

        MOV     RDX,U64 CMemUsed.hc[RSI]
#endif
        CMP     RAX,MEM_HEAP_HASH_SIZE
        JAE     @@50

#assert CMemUnused.size == CMemUsed.size
    //      MOV     U64 CMemUnused.size[RSI],RAX

        MOV     RBX,U64 CHeapCtrl.heap_hash[RAX+RDX]
        MOV     U64 CMemUnused.next[RSI],RBX
        MOV     U64 CHeapCtrl.heap_hash[RAX+RDX],RSI
        JMP     @@55

@@50:   SUB     RSI,sizeof(CMemBlk)
        PUSH    RDX
        PUSH    RDX
        PUSH    RSI
        CALL    &MemPagTaskFree
        POP     RDX

@@55:   LOCK
        BTR     U32 CHeapCtrl.locked_flags[RDX],HClf_LOCKED
        POPFD
RFREE_DONE:
        POP     RDI
        POP     RSI
        POP     RBP
        RET1    8
    //************************************
}

_extern _RMALLOC U8* RMAlloc(I64 size, CTask* mem_task = NULL);
_extern _RFREE U0 RFree(U8* addr);

U8* RCAlloc(I64 size, CTask* mem_task = NULL)
{
    U8* res = RMAlloc(size, mem_task);
    if (res) {
        MemSet(res, NULL, size);
    }
    return res;
}

class @rmalloc_request
{
    U64 res_addr;
    CTask* task;
    U64 bytes;
    U64 ptr;
    Bool type;
    Bool kick;
};

U0 @rmalloc_task()
{
    U64* ptr = RMALLOC_REQUEST_PTR;
    @rmalloc_request* r = NULL;
    while (1) {
        r = *ptr;
        if (r) {
            switch (r->type) {
            case RMALLOC_TYPE_MALLOC:
                LXchgI64(r->res_addr, RMAlloc(r->bytes, r->task));
                break;
            case RMALLOC_TYPE_CALLOC:
                LXchgI64(r->res_addr, RCAlloc(r->bytes, r->task));
                break;
            case RMALLOC_TYPE_FREE:
                RFree(r->ptr);
                break;
            default:
                break;
            }
            LXchgU8(&r->kick, 1);
            *ptr = NULL;
        }
        Yield;
    }
}

U64 RMAllocOper(I64 size, CTask* task = NULL, Bool type = RMALLOC_TYPE_MALLOC, U64 addr = NULL)
{
    I64 count = 0;
    U64 res = NULL;
    U64* ptr = RMALLOC_REQUEST_PTR;
    @rmalloc_request r;

    r.res_addr = &res;
    r.bytes = size;
    r.task = task;
    r.ptr = addr;
    r.type = type;
    r.kick = FALSE;

retry_rmalloc:
    count = 0;
    while (*ptr)
        Busy(RMALLOC_BUSY_WAIT);
    LXchgI64(ptr, &r);
    while (!r.kick) {
        ++count;
        if (count > RMALLOC_TIMEOUT)
            goto retry_rmalloc;
        Busy(RMALLOC_BUSY_WAIT);
    }

    return res;
}

U64 MAlloc2(I64 size, CTask* task = NULL)
{
    return RMAllocOper(size, task);
}

U64 CAlloc2(I64 size, CTask* task = NULL)
{
    return RMAllocOper(size, task, RMALLOC_TYPE_CALLOC);
}

U0 Free2(U8* addr)
{
    RMAllocOper(NULL, NULL, RMALLOC_TYPE_FREE, addr);
}

CTask* sys_malloc_task = Spawn(&@rmalloc_task, , "RMAlloc Task", RMALLOC_TASK_CPU);

Suspend(sys_winmgr_task);
@patch_jmp_rel32(&MAlloc, &MAlloc2);
@patch_jmp_rel32(&CAlloc, &CAlloc2);
@patch_jmp_rel32(&Free, &Free2);
Suspend(sys_winmgr_task, FALSE);
