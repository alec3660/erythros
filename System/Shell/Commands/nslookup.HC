I64 @shell_cmd_nslookup(@shell* sh, I64 argc, U8** argv)
{
    if (argc < 2) {
        // TODO: Interactive mode
        return 0;
    }
    if (argc > 2) {
        // TODO: Server argument
    }

    NetInfoRequest* req = @net_info_request;
    U32 resolver_ip = req->dns_server_address;
    Free(req);

    Stdio.WriteLine(sh, "Server:         %d.%d.%d.%d\n", resolver_ip.u8[3],
        resolver_ip.u8[2], resolver_ip.u8[1], resolver_ip.u8[0]);

    Stdio.WriteLine(sh, "Address:        %d.%d.%d.%d#53\n\n", resolver_ip.u8[3],
        resolver_ip.u8[2], resolver_ip.u8[1], resolver_ip.u8[0]);

    U32 res_ip = @dns_query(argv[1]);

    if (res_ip == U32_MAX) {
        Stdio.WriteLine(sh, "** server can't find %s: NXDOMAIN\n\n", argv[1]);
        return 1;
    }
    Stdio.WriteLine(sh, "Non-authoritative answer:\n");
    Stdio.WriteLine(sh, "Name:   %s\n", argv[1]);
    Stdio.WriteLine(sh, "Address: %d.%d.%d.%d\n\n", res_ip.u8[3], res_ip.u8[2],
        res_ip.u8[1], res_ip.u8[0]);
    return 0;
}