// Before continuing, we:

// 1. Mark memory in code heap below 0x1000000 as used.
sys_code_bp->mem_free_lst->next->pags = 0;

// 2. Free up 64MB at bottom of code heap for non-HolyC programs
sys_code_bp->mem_free_lst = ShrinkMemBlkByPags(sys_code_bp->mem_free_lst, 131072);

// 3. Set mem_task

CTask* erythros_mem_task = sys_malloc_task;

U0 NoBeep(I8, Bool) {};
@patch_jmp_rel32(&Beep, &NoBeep); // Don't delay on beep when entering debugger
//@patch_jmp_rel32(&Fault2, &Reboot); // Reboot instead of crashing to the debugger

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

@patch_jmp_rel32(&BlkDevLock, &BlkDevLock2); // Patch BlkDevLock so we don't deadlock on multiple tasks reading from virtio disk
@patch_jmp_rel32(&DrvLock, &DrvLock2);       // Patch DrvLock so we don't deadlock on multiple tasks reading from virtio disk
