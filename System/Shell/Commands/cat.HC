U8* @cat_buf_from_url_string(U8* url_string, I64* size)
{
    U8* fetch_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, Fs);
    @http_response* resp = fetch(url_string, fetch_buffer);
    if (!resp)
        return 0;
    U8* buf = NULL;
    if (resp->body.length) {
        buf = CAlloc(resp->body.length);
        MemCpy(buf, resp->body.data, resp->body.length);
    }
    *size = resp->body.length;
    Free(fetch_buffer);
    return buf;
}

I64 @shell_cmd_cat(@shell* sh, I64 argc, U8** argv)
{
    if (argc < 2)
        return 0;
    I64 i;
    I64 j;
    I64 size = 0;
    U8* filename = NULL;
    U8* buf = NULL;
    for (i = 1; i < argc; i++) {
        if (!MemCmp(argv[i], "http://", 7) || !MemCmp(argv[i], "https://", 8)) {
            buf = @cat_buf_from_url_string(argv[i], &size);
        } else {
            filename = @shell_expand_relative_path(sh, argv[i]);
            buf = FileSystem.ReadFile(filename, &size);
        }
        for (j = 0; j < size; j++)
            FifoU8Ins(sh->output, buf[j]);
        Free(buf);
        Free(filename);
    }
    return 0;
}