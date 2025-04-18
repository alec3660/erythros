#define INT_LAST_VALID_ENTRY 1 << 2
#define INT_IOC 1 << 3
#define INT_FIFO_ERR 1 << 4

#define BDL_BUF_SIZE 2044
#define PCM_BUF_SIZE 2048
#define MAX_BDLS 32

#define PCM_IN 0
#define PCM_OUT 1
#define MIC_IN 2

// Native Audio Mixer registers (all U16)

#define RESET 0x00          // Reset Register
#define MASTER_VOL 0x02     // Set Master Output Volume
#define MIC_VOL 0x0E        // Set Microphone Volume
#define PCM_VOL 0x18        // Set Output Volume of PCM patterns
#define REC_SLC 0x1A        // Select Input Device
#define REC_GAIN 0x1C       // Set Input Gain
#define MIC_GAIN 0x1E       // Set Gain of Microphone
#define EXT_ID 0x28         // Supported extended functions
#define EXT_CTRL 0x2A       // Enabling extended functions
#define EXT_FRONT_RATE 0x2C // Sample rate of front speaker

// Native Audio Bus Master registers

#define PCM_INPUT_REG_BOX \
    0x00 // NABM register box for PCM IN (sizeof NABM register box)
#define PCM_OUTPUT_REG_BOX \
    0x10 // NABM register box for PCM OUT (sizeof NABM register box)
#define MIC_INPUT_REG_BOX \
    0x20                // NABM register box for Microphone (sizeof NABM register box)
#define GLOBAL_CTL 0x2C // Global Control Register (U32)
#define GLOBAL_STS 0x30 // Global Status Register (U32)

// NABM register box registers

#define BUFFER_DSC_ADDR 0x00 // Physical Address of Buffer Descriptor List (U32)
#define CUR_ENTRY_VAL \
    0x04                      // Number of Actual Processed Buffer Descriptor Entry (U8)
#define LAST_VALID_ENTRY 0x05 // Number of all Descriptor Entries (U8)
#define TRANSFER_STS 0x06     // Status of Transferring Data (U16)
#define CUR_IDX_PROC_SAMPLES \
    0x08                 // Number of Transferred Samples in Actual Processed Entry (U16)
#define PRCSD_ENTRY 0x0A // Number of Actual Processed Buffer Entry (U8)
#define BUFFER_CNT \
    0x0B // Most Important Register for controlling Transfers (U8)

class @ac97_bdl_entry
{
    U32 addr;
    U16 length; // length - 1
    U16 flags;
};

class @ac97_bdl
{
    @ac97_bdl_entry entries[32];
};

class @ac97
{
    @pci_info pci;
    @ac97_bdl* bdl[3];
    U16 nam;
    U16 nabm;
};

@ac97 AC97;

U0 @ac97_fill_buffer()
{
    I64 idx = InU8(AC97.nabm + PCM_OUTPUT_REG_BOX + LAST_VALID_ENTRY);
    U32* buf = AC97.bdl[PCM_OUT]->entries[idx].addr;
    @audio_mix_output(buf, BDL_BUF_SIZE);
    OutU8(AC97.nabm + PCM_OUTPUT_REG_BOX + LAST_VALID_ENTRY, ++idx);
}

U0 @ac97_int_handler()
{
    U16 status = InU16(AC97.nabm + PCM_OUTPUT_REG_BOX + TRANSFER_STS);
    if (status & INT_IOC) {
        @ac97_fill_buffer;
        OutU16(AC97.nabm + PCM_OUTPUT_REG_BOX + TRANSFER_STS, 0x1C);
    }
}

I64 @ac97_init()
{
    I64 i;
    I64 j;
    // Scan for device
    j = PCIClassFind(0x040100, 0);
    if (j < 0) {
    device_not_found:
        AdamLog("\n[AC'97] Device not found\n");
        return -1;
    }
    @get_pci_info(j, &AC97.pci);

    if (AC97.pci.vendor_id != 0x8086 || AC97.pci.device_id != 0x2415)
        goto device_not_found;

    AC97.nam = AC97.pci.bar[0] & 0xFFFFFF00;
    AC97.nabm = AC97.pci.bar[1] & 0xFFFFFF00;

    // Enable port IO, disable MMIO
    PCIWriteU8(j.u8[2], j.u8[1], j.u8[0], 0x4, 5);

    OutU32(AC97.nabm + GLOBAL_CTL, 0x03);
    OutU16(AC97.nam + RESET, 0xFFFF);

    // Set PCM Output to Max volume
    OutU16(AC97.nam + PCM_VOL, 0x0000);

    // Allocate Buffer Descriptor Lists
    AC97.bdl[PCM_IN] = CAllocAligned(sizeof(@ac97_bdl), 4096, Fs->code_heap);
    AC97.bdl[PCM_OUT] = CAllocAligned(sizeof(@ac97_bdl), 4096, Fs->code_heap);
    AC97.bdl[MIC_IN] = CAllocAligned(sizeof(@ac97_bdl), 4096, Fs->code_heap);

    for (i = 0; i < MAX_BDLS; i++) {
        AC97.bdl[PCM_OUT]->entries[i].addr = CAllocAligned(PCM_BUF_SIZE, 4096, Fs->code_heap);
        AC97.bdl[PCM_OUT]->entries[i].length = BDL_BUF_SIZE / 2;
        AC97.bdl[PCM_OUT]->entries[i].flags = 1 << 15;
    }

    // Set addresses of Buffer Descriptor Lists
    // OutU32(AC97.nabm + PCM_INPUT_REG_BOX + BUFFER_DSC_ADDR, AC97.bdl[PCM_IN]);
    OutU32(AC97.nabm + PCM_OUTPUT_REG_BOX + BUFFER_DSC_ADDR, AC97.bdl[PCM_OUT]);
    // OutU32(AC97.nabm + MIC_INPUT_REG_BOX + BUFFER_DSC_ADDR, AC97.bdl[MIC_IN]);

    // Set Master Volume
    OutU16(AC97.nam + MASTER_VOL, 0x0F0F);

    // Stop playing sound
    OutU8(AC97.nabm + PCM_OUTPUT_REG_BOX + BUFFER_CNT, 0);

    // Fill one buffers
    @ac97_fill_buffer;

    // Enable interrupt handler
    @pci_register_int_handler(&@ac97_int_handler);

    // Start playing sound
    OutU8(AC97.nabm + PCM_OUTPUT_REG_BOX + BUFFER_CNT, 1);

    return 0;
}

@ac97_init;

"ac97 ";