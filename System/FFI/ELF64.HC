#define EI_NIDENT 16
#define EM_X86_64 0x3E
#define ET_EXEC 2
#define ET_DYN 3

U0 @elf64_debug_print(U8 fmt, ...)
{
    // FIXME: Remove unnecessary debug_print statements and PrintErr for errors.
    no_warn fmt, argc, argv;
}

class Elf64_Ehdr {
    U8 e_ident[EI_NIDENT]; /* Magic number and other info */
    U16 e_type;            /* Object file type */
    U16 e_machine;         /* Architecture */
    U32 e_version;         /* Object file version */
    U64 e_entry;           /* Entry point virtual address */
    U64 e_phoff;           /* Program header table file offset */
    U64 e_shoff;           /* Section header table file offset */
    U32 e_flags;           /* Processor-specific flags */
    U16 e_ehsize;          /* ELF header size in bytes */
    U16 e_phentsize;       /* Program header table entry size */
    U16 e_phnum;           /* Program header table entry count */
    U16 e_shentsize;       /* Section header table entry size */
    U16 e_shnum;           /* Section header table entry count */
    U16 e_shstrndx;        /* Section header string table index */
};

class Elf64_Shdr {
    U32 sh_name;      /* Section name (string tbl index) */
    U32 sh_type;      /* Section type */
    U64 sh_flags;     /* Section flags */
    U64 sh_addr;      /* Section virtual addr at execution */
    U64 sh_offset;    /* Section file offset */
    U64 sh_size;      /* Section size in bytes */
    U32 sh_link;      /* Link to another section */
    U32 sh_info;      /* Additional section information */
    U64 sh_addralign; /* Section alignment */
    U64 sh_entsize;   /* Entry size if section holds table */
};

class Elf64_Sym {
    U32 st_name;  /* Symbol name (string tbl index) */
    U8 st_info;   /* Symbol type and binding */
    U8 st_other;  /* Symbol visibility */
    U16 st_shndx; /* Section index */
    U64 st_value; /* Symbol value */
    U64 st_size;  /* Symbol size */
};

class PLT_entry {
    U8 pad[0x10];
};

class RELA_entry {
    U64 r_offset;
    U64 r_info;
    I64 r_addend;
};

class Elf {
    union {
        U8* u8;
        Elf64_Ehdr* ehdr;
    } I64 size;
    U8* dynstr;
    Elf64_Sym* dynsym;
    PLT_entry* plt;
    RELA_entry* rela_dyn;
    RELA_entry* rela_plt;
    Elf64_Sym* strtab;
    Elf64_Sym* symtab;
    I64 rela_dyn_size;
    I64 rela_plt_size;
    I64 strtab_size;
    I64 symtab_size;
};

U0 (*_start)();

U0 unimplemented_symbol()
{
    I32 s = 0xDEADF00D;
    PrintWarn("Unimplemented symbol: %s\n", s);
    Dbg;
    while (1)
        Sleep(1);
}

Bool is_valid_elf(Elf* elf)
{
    Bool res = TRUE;
    if (MemCmp(elf->u8 + 1, "ELF", 3)) {
        @elf64_debug_print("Invalid signature (not ELF).\n");
        res = FALSE;
    }
    if (elf->ehdr->e_type != ET_EXEC && elf->ehdr->e_type != ET_DYN) {
        @elf64_debug_print("Invalid object file type.\n");
        res = FALSE;
    }
    if (elf->ehdr->e_machine != EM_X86_64) {
        @elf64_debug_print("Invalid architecture.\n");
        res = FALSE;
    }
    return res;
}

U0 process_elf_section_header_table(Elf* elf)
{
    Elf64_Shdr* shdr = elf->u8 + elf->ehdr->e_shoff;
    Elf64_Shdr* shdr_shstrtab = shdr + elf->ehdr->e_shstrndx;
    U8* shstrtab = elf->u8 + shdr_shstrtab->sh_offset;
    I64 i = 0;
    while (i < elf->ehdr->e_shnum) {
        if (!StrCmp(shstrtab + shdr->sh_name, ".symtab")) {
            @elf64_debug_print("found symtab at 0x%08x, size = %d\n", shdr->sh_offset,
                shdr->sh_size);
            elf->symtab = elf->u8 + shdr->sh_offset;
            elf->symtab_size = shdr->sh_size;
        }
        if (!StrCmp(shstrtab + shdr->sh_name, ".strtab")) {
            @elf64_debug_print("found strtab at 0x%08x, size = %d\n", shdr->sh_offset,
                shdr->sh_size);
            elf->strtab = elf->u8 + shdr->sh_offset;
            elf->strtab_size = shdr->sh_size;
        }
        if (shdr->sh_addr) {
            MemCpy(shdr->sh_addr, elf->u8 + shdr->sh_offset, shdr->sh_size);
            if (!StrCmp(shstrtab + shdr->sh_name, ".dynstr"))
                elf->dynstr = shdr->sh_addr;
            if (!StrCmp(shstrtab + shdr->sh_name, ".dynsym"))
                elf->dynsym = shdr->sh_addr;
            if (!StrCmp(shstrtab + shdr->sh_name, ".plt"))
                elf->plt = shdr->sh_addr;
            if (!StrCmp(shstrtab + shdr->sh_name, ".rela.dyn")) {
                elf->rela_dyn = shdr->sh_addr;
                elf->rela_dyn_size = shdr->sh_size / shdr->sh_entsize;
            }
            if (!StrCmp(shstrtab + shdr->sh_name, ".rela.plt")) {
                elf->rela_plt = shdr->sh_addr;
                elf->rela_plt_size = shdr->sh_size / shdr->sh_entsize;
            }
            if (!StrCmp(shstrtab + shdr->sh_name, ".bss") || !StrCmp(shstrtab + shdr->sh_name, ".tbss")) {
                MemSet(shdr->sh_addr, NULL, shdr->sh_size);
                @elf64_debug_print(
                    "Zeroed out section '%s' at physical address 0x%06x, size = %d bytes\n",
                    shstrtab + shdr->sh_name, shdr->sh_addr, shdr->sh_size);
            } else
                @elf64_debug_print(
                    "MemCpy section '%s' to physical address 0x%06x, size = %d bytes\n",
                    shstrtab + shdr->sh_name, shdr->sh_addr, shdr->sh_size);
            if (!StrCmp(shstrtab + shdr->sh_name, ".bss")) {
                MemSet(shdr->sh_addr, NULL, shdr->sh_size);
                @elf64_debug_print("MemSet section '%s' at physical address 0x%06x to NULL, "
                                   "size = %d bytes\n",
                    shstrtab + shdr->sh_name, shdr->sh_addr, shdr->sh_size);
            }
        }
        shdr++;
        i++;
    }
}

U0 process_elf_rela_dyn_entries(Elf* elf)
{
    I64 i;
    U8* entry_name;
    RELA_entry* rela_dyn = elf->rela_dyn;
    for (i = 0; i < elf->rela_dyn_size; i++) {
        entry_name = elf->dynstr + elf->dynsym[(rela_dyn->r_info >> 32)].st_name;
        @elf64_debug_print("rela_dyn->r_offset = %08x\n", rela_dyn->r_offset);
        @elf64_debug_print("entry name = '%s'\n", entry_name);
        if (!StrCmp(entry_name, "__libc_start_main")) {
            *(rela_dyn->r_offset)(U64*) = &_main;
            @elf64_debug_print("Set value for .rela.dyn entry '%s' to: &_main\n",
                entry_name);
        }
        if (!StrCmp(entry_name, "stdin")) {
            *(rela_dyn->r_offset)(U64*) = 0;
            @elf64_debug_print("Set value for .rela.dyn entry '%s' to: %d\n", entry_name, 0);
        }
        if (!StrCmp(entry_name, "stdout")) {
            *(rela_dyn->r_offset)(U64*) = 1;
            @elf64_debug_print("Set value for .rela.dyn entry '%s' to: %d\n", entry_name, 1);
        }
        if (!StrCmp(entry_name, "stderr")) {
            *(rela_dyn->r_offset)(U64*) = 2;
            @elf64_debug_print("Set value for .rela.dyn entry '%s' to: %d\n", entry_name, 2);
        }
        rela_dyn++;
    }
}

CHashClass* get_symbol_hash_entry(U8* entry_name)
{
    I64 i;
    CHashSrcSym* sym;
    CHashTable* tbl = Fs->hash_table;
    while (tbl) {
        for (i = 0; i < tbl->mask; i++) {
            sym = tbl->body[i];
            while (sym) {
                if (sym->type == HTT_CLASS)
                    if (!StrCmp(sym->str, entry_name))
                        return sym;
                sym = sym->next;
            }
        }
        tbl = tbl->next;
    }
    return NULL;
}

U64 get_symbol_address(U8* entry_name)
{
    CHash* h = HashFind(entry_name, Fs->hash_table, Fs->hash_table->mask);
    if (!h)
        return NULL;
    switch (h->type) {
    case HTT_GLBL_VAR:
        return h(CHashGlblVar*)->data_addr;
        break;
    case HTT_FUN:
        return h(CHashFun*)->exe_addr;
        break;
    default:
        return NULL;
        break;
    }
    return NULL;
}

U0 process_elf_rela_plt_entries(Elf* elf)
{
    I64 i;
    U32 handler;
    U32* patch;
    U8* entry_name;
    Bool symbol_exists;
    PLT_entry* plt = elf->plt;
    RELA_entry* rela_plt = elf->rela_plt;
    plt++;
    for (i = 0; i < elf->rela_plt_size; i++) {
        symbol_exists = FALSE;
        entry_name = elf->dynstr + elf->dynsym[(rela_plt->r_info >> 32)].st_name;
        handler = MAlloc(sizeof(unimplemented_symbol), erythros_mem_task->code_heap);
        MemCpy(handler, &unimplemented_symbol, sizeof(unimplemented_symbol));
        patch = handler + 0x0A;
        *patch = entry_name;
        @patch_jmp_rel32(plt, handler);
        @patch_call_rel32(handler + 0x16, &PrintErr);
        //@patch_call_rel32(handler + 0x21, &_exit);
        if (!StrCmp(entry_name, "__libc_start_main")) {
            symbol_exists = TRUE;
            @patch_jmp_rel32(plt, &_main);
            @elf64_debug_print("Set value for .rela.plt entry '%s' to &_main\n", entry_name);
        }
        if (get_symbol_address(entry_name)) {
            symbol_exists = TRUE;
            @patch_jmp_rel32(plt, get_symbol_address(entry_name));
            @elf64_debug_print("Set value for .rela.plt entry '%s' to &%s\n", entry_name,
                entry_name);
        }
        if (!symbol_exists)
            @elf64_debug_print(
                "Set value for .rela.plt entry '%s' to &unimplemented_symbol\n",
                entry_name);
        rela_plt++;
        plt++;
    }
}

U0 load_elf(...)
{
    if (argc < 1) {
        PrintErr("Not enough arguments.\n");
        return;
    }
    if (!FileFind(argv[0])) {
        PrintErr("File not found: %s\n", argv[0]);
        return;
    }

    Elf elf;
    elf.u8 = FileRead(argv[0], &elf.size);
    @elf64_debug_print("Load file '%s', size = %d bytes\n", argv[0], elf.size);

    if (!is_valid_elf(&elf)) {
        PrintErr("File is not a valid ELF x86-64 executable.\n");
        return;
    }

    process_elf_section_header_table(&elf);
    process_elf_rela_dyn_entries(&elf);
    process_elf_rela_plt_entries(&elf);

    _start = elf.ehdr->e_entry;
    elf_argc = argc;
    elf_argv = argv;
}