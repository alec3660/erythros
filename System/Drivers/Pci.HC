#define PCI_INTH_MAX 16

U64 @pci_int_handler[PCI_INTH_MAX];

class @pci_info
{
    U16 vendor_id;
    U16 device_id;
    U16 command;
    U16 status;
    U32 _class;
    U32 bar[6];
    U32 cap_pointer;
};

class @pci_cap
{
    U8 cap_vndr;   /* Generic PCI field: PCI_CAP_ID_VNDR */
    U8 cap_next;   /* Generic PCI field: next ptr. */
    U8 cap_len;    /* Generic PCI field: capability length */
    U8 cfg_type;   /* Identifies the structure. */
    U8 bar;        /* Where to find it. */
    U8 padding[3]; /* Pad to full dword. */
    U32 offset;    /* Offset within bar. */
    U32 length;    /* Length of the structure, in bytes. */
};

U0 @get_pci_info(I64 i, @pci_info* pci)
{
    I64 j;
    pci->vendor_id = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], 0x0) & 0xFFFF;
    pci->device_id = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], 0x0) >> 16;
    pci->command = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], 0x4) & 0xFFFF;
    pci->status = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], 0x4) >> 16;
    pci->_class = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], 0x8) >> 24;
    for (j = 0; j < 6; j++)
        pci->bar[j] = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], 0x10 + (0x04 * j));
}

U0 @get_pci_cap(I64 i, @pci_cap* cap, I64 idx)
{
    I64 base = 0x40 + (idx * 16);
    U32 u32;
    u32 = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], base);
    cap->cap_vndr = u32.u8[0];
    cap->cap_next = u32.u8[1];
    cap->cap_len = u32.u8[2];
    cap->cfg_type = u32.u8[3];
    u32 = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], base + 0x04);
    cap->bar = u32.u8[0];
    cap->offset = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], base + 0x08);
    cap->length = PCIReadU32(i.u8[2], i.u8[1], i.u8[0], base + 0x0c);
}

U0 @pci_reroute_interrupts(I64 base, I64 cpu)
{
    I64 i;
    U8* da = dev.uncached_alias + IOAPIC_REG;
    U32* _d = dev.uncached_alias + IOAPIC_DATA;

    for (i = 0; i < 4; i++) {
        *da = IOREDTAB + i * 2 + 1;
        *_d = dev.mp_apic_ids[cpu] << 24;
        *da = IOREDTAB + i * 2;
        *_d = 0x4000 + base + i;
    }
}

I64 @pci_register_int_handler(U64 handler)
{
    if (!handler)
        return -1;
    I64 i = 0;
    while (@pci_int_handler[i])
        i++;
    if (i > PCI_INTH_MAX - 1)
        return -1;
    @pci_int_handler[i] = handler;
    return 0;
}

interrupt U0 @pci_interrupt_handler()
{
    I64 i;
    for (i = 0; i < PCI_INTH_MAX; i++)
        if (@pci_int_handler[i])
            Call(@pci_int_handler[i]);
    *(dev.uncached_alias + LAPIC_EOI)(U32*) = 0;
}

MemSet(&@pci_int_handler, NULL, sizeof(U64) * PCI_INTH_MAX);
IntEntrySet(0x40, &@pci_interrupt_handler, IDTET_IRQ);
IntEntrySet(0x41, &@pci_interrupt_handler, IDTET_IRQ);
IntEntrySet(0x42, &@pci_interrupt_handler, IDTET_IRQ);
IntEntrySet(0x43, &@pci_interrupt_handler, IDTET_IRQ);
@pci_reroute_interrupts(0x40, 0);

"pci ";