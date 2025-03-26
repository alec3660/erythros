class @stdio
{
    U0 (*ReadLine)(@shell* sh, U8* prompt, U8* str);
    U0 (*WriteLine)(@shell* sh, U8* fmt, ...);
};

U0 @stdio_write_line(@shell* sh, U8* fmt, ...)
{
    if (!sh)
        return;
    if (!fmt || !sh->output)
        return;
    U8* buf;
    if (argc) {
        buf = StrPrintJoin(NULL, fmt, argc, argv);
    } else {
        buf = StrNew(fmt, erythros_mem_task);
    }
    I64 i;
    for (i = 0; i < StrLen(buf); i++)
        FifoU8Ins(sh->output, buf[i]);
    Free(buf);
}

I64 @stdio_handle_control_chars(@shell* sh)
{
    if (!FifoU8Cnt(sh->input))
        return 0;
    U8 char;
    FifoU8Rem(sh->input, &char);
    switch (char) {
    case '[':
        if (!FifoU8Cnt(sh->input))
            return 0;
        FifoU8Rem(sh->input, &char);
        switch (char) {
        case 'A':
            return SC_CURSOR_UP;
            break;
        case 'B':
            return SC_CURSOR_DOWN;
            break;
        case 'D':
            return SC_CURSOR_LEFT;
            break;
        case 'C':
            return SC_CURSOR_RIGHT;
            break;
        default:
            return 0;
            break;
        }
        break;
    default:
        return 0;
        break;
    }
}

U0 @stdio_read_line_history_back(@shell* sh, I64 pos)
{
    if (sh->history.index < 0)
        sh->history.index = 0;
    while (pos > 0) {
        FifoU8Ins(sh->input, '\x8');
        pos--;
    }
    U8* char = sh->history.entries[sh->history.index];
    while (*char)
        FifoU8Ins(sh->input, *char ++);
    if (sh->history.index > -1) {
        sh->history.index--;
    }
}

U0 @stdio_read_line_history_fwd(@shell* sh, I64 pos)
{
    if (sh->history.index < sh->history.pos) {
        sh->history.index++;
    }
    if (sh->history.index > sh->history.pos)
        sh->history.index = sh->history.pos;
    while (pos > 0) {
        FifoU8Ins(sh->input, '\x8');
        pos--;
    }
    U8* char = sh->history.entries[sh->history.index];
    while (*char)
        FifoU8Ins(sh->input, *char ++);
}

I64 @stdio_read_line_autocomplete_cmd_count(U8* str)
{
    I64 cnt = 0;

    I64 i;
    CHashSrcSym* sym;
    CHashTable* tbl = adam_task->hash_table;
    while (tbl) {
        for (i = 0; i < tbl->mask; i++) {
            sym = tbl->body[i];
            while (sym) {
                if (sym->type == HTT_FUN) {
                    if (!MemCmp(sym->str, str, StrLen(str))) {
                        ++cnt;
                    }
                }
                sym = sym->next;
            }
        }
        tbl = tbl->next;
    }
    return cnt;
}

U0 @stdio_read_line_autocomplete_cmd(@shell* sh, U8* str, U8* line, I64* pos)
{
    I64 cnt = 0;

    I64 i;
    U8* ac_ch_ptr = NULL;
    CHashSrcSym* sym;
    CHashTable* tbl = adam_task->hash_table;
    while (tbl) {
        for (i = 0; i < tbl->mask; i++) {
            sym = tbl->body[i];
            while (sym) {
                if (sym->type == HTT_FUN) {
                    if (!MemCmp(sym->str, str, StrLen(str))) {
                        ac_ch_ptr = sym->str + StrLen(str);
                        while (*ac_ch_ptr) {
                            String.Append(line, "%c", *ac_ch_ptr);
                            FifoU8Ins(sh->output, *ac_ch_ptr);
                            ++pos[0];
                            ++ac_ch_ptr;
                        }
                        String.Append(line, " ");
                        FifoU8Ins(sh->output, ' ');
                        ++pos[0];
                        return;
                    }
                }
                sym = sym->next;
            }
        }
        tbl = tbl->next;
    }
}

I64 @stdio_read_line_autocomplete_sort_cmds(U8** e1, U8** e2)
{
    return StrCmp(*e1, *e2);
}

U0 @stdio_read_line_autocomplete_list_cmds(@shell* sh, U8* prompt, U8* str, U8* line, I64* pos, I64 cmd_count)
{
    I64 cnt = 0;

    I64 i;
    U8** cmds = CAlloc(sizeof(U8*) * cmd_count);
    CHashSrcSym* sym;
    CHashTable* tbl = adam_task->hash_table;
    while (tbl) {
        for (i = 0; i < tbl->mask; i++) {
            sym = tbl->body[i];
            while (sym) {
                if (sym->type == HTT_FUN) {
                    if (!MemCmp(sym->str, str, StrLen(str))) {
                        if (!cnt) {
                            @stdio_write_line(sh, "\n");
                        }
                        cmds[cnt] = sym->str + StrLen("@shell_cmd_");
                        ++cnt;
                    }
                }
                sym = sym->next;
            }
        }
        tbl = tbl->next;
    }
    if (cnt) {
        QSort(cmds, cnt, sizeof(U8*), &@stdio_read_line_autocomplete_sort_cmds);
        for (i = 0; i < cnt; i++) {
            @stdio_write_line(sh, "%s\n", cmds[i]);
        }
        @stdio_write_line(sh, "%s%s", prompt, line);
    }
    Free(cmds);
}

U0 @stdio_read_line_autocomplete(@shell* sh, U8* prompt, U8* str, I64* pos)
{
    U8 ac_buf[4096];
    I64 space_count = StrOcc(str, ' ');
    I64 cmd_count = 0;
    switch (space_count) {
    case 0:
        StrPrint(ac_buf, "@shell_cmd_%s", str);
        cmd_count = @stdio_read_line_autocomplete_cmd_count(ac_buf);
        switch (cmd_count) {
        case 1:
            @stdio_read_line_autocomplete_cmd(sh, ac_buf, str, pos);
            break;
        default:
            // TODO: if we have >1, print the list
            @stdio_read_line_autocomplete_list_cmds(sh, prompt, ac_buf, str, pos, cmd_count);
            // and reprint str below it?
            break;
        }
    default:
        break;
    }
}

U0 @stdio_read_line(@shell* sh, U8* prompt, U8* str)
{
    U8 char = NULL;
    U8 line[4096];
    MemSet(line, 0, 4096);
    I64 pos = 0;
    if (!str || !sh)
        return;
    if (prompt) {
        @stdio_write_line(sh, prompt);
    }
    sh->history.index = sh->history.pos - 1;
    while (char != '\x3' && char != '\n') {
        while (FifoU8Cnt(sh->input)) {
            FifoU8Rem(sh->input, &char);
            switch (char) {
            case '\t':
                @stdio_read_line_autocomplete(sh, prompt, line, &pos);
                break;
            case 3:
                @stdio_write_line(sh, "^C");
                break;
            case 8:
                if (pos > 0) {
                    line[StrLen(line) - 1] = NULL;
                    FifoU8Ins(sh->output, '\x8');
                    pos--;
                } else
                    FifoU8Ins(sh->output, '\x7');
                break;
            case 13:
                break;
            case 27:
                switch (@stdio_handle_control_chars(sh)) {
                case SC_CURSOR_UP:
                    @stdio_read_line_history_back(sh, pos);
                    break;
                case SC_CURSOR_DOWN:
                    @stdio_read_line_history_fwd(sh, pos);
                    break;
                default:
                    break;
                }
                break;
            case 32...127:
                line[pos] = char;
                FifoU8Ins(sh->output, char);
                pos++;
                break;
            };
        }
        Sleep(1);
    }
    line[pos] = NULL;
    switch (char) {
    case '\x3':
        StrCpy(str, "");
        break;
    case '\n':
        StrCpy(str, &line);
        break;
    };
    FifoU8Ins(sh->output, '\n');
}

@stdio Stdio;

Stdio.ReadLine = &@stdio_read_line;
Stdio.WriteLine = &@stdio_write_line;

"stdio ";