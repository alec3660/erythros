I64 @shell_cmd_ping(@shell* sh, I64 argc, U8** argv)
{
    if (argc < 2) {
        Stdio.WriteLine(sh, "ping: usage error: Destination address required\n");
        return 1;
    }
    U8* host = argv[1];
    if (!host || !StrLen(host)) {
        Stdio.WriteLine(sh, "Invalid host specified\n");
        return PING_ERR_INVALID_HOST;
    }
    I64 count = 4;

    U32 addr = @dns_query(host);
    if (addr == U32_MAX) {
        Stdio.WriteLine(sh, "Host not found\n");
        return PING_ERR_HOST_NOT_FOUND;
    }

    U16 iden = (RandU16 * SysTimerRead) & 0xFFFF;
    I64 start_jiffies;
    U32 reply = NULL;
    I64 res = 0;
    U16 seq = 0;
    I64 loss = 0;

    IcmpRequest* request = CAlloc(sizeof(IcmpRequest), Fs->code_heap);

    Stdio.WriteLine(sh, "PING %s (%d.%d.%d.%d): %d data bytes\n",
        host, addr.u8[3], addr.u8[2], addr.u8[1], addr.u8[0], PING_PAYLOAD_SIZE);

    I64 i;
    for (i = 0; i < count; i++) {
        start_jiffies = cnts.jiffies;
        reply = @icmp_echo_request(addr, iden, seq, request, i);
        if (!reply) {
            Stdio.WriteLine(sh, "Request timeout for icmp_seq %d\n", seq);
            ++loss;
            res = 1;
        } else {
            Stdio.WriteLine(sh, "%d bytes from %d.%d.%d.%d: icmp_seq=%d ttl=%d time=%d ms\n",
                reply.u16[1], addr.u8[3], addr.u8[2], addr.u8[1], addr.u8[0], seq, reply.u16[0], cnts.jiffies - start_jiffies);
        }
        while (cnts.jiffies < start_jiffies + 1000 && i < (count - 1))
            Sleep(1);
        ++seq;
    }

    Free(request);

    Stdio.WriteLine(sh, "--- %d.%d.%d.%d ping statistics ---\n", addr.u8[3], addr.u8[2], addr.u8[1], addr.u8[0]);
    Stdio.WriteLine(sh, "%d packets transmitted, %d packets received, %0f",
        seq, seq - loss, (loss * 1.0 / seq * 1.0) * 100);
    Stdio.WriteLine(sh, "%c", 37);
    Stdio.WriteLine(sh, " packet loss\n");

    return res;
}
