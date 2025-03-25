#define ETHERNET_FRAME_SIZE 1400

I64 @shell_cmd_ifconfig(@shell* sh, I64 argc, U8** argv)
{
    NetInfoRequest* req = @net_info_request;

    U64 en0_mac = req->mac_address;
    U32 en0_addr = req->ipv4_address;
    U32 en0_mask = req->ipv4_netmask;
    U32 en0_bcast = req->ipv4_address | ~req->ipv4_netmask;

    U8 buf[512];

    Stdio.WriteLine(sh, "en0: flags=4163<UP,BROADCAST,RUNNING,MULTICAST>  mtu %d\n",
        ETHERNET_FRAME_SIZE - 18);

    Stdio.WriteLine(sh,
        "        inet %d.%d.%d.%d  netmask %d.%d.%d.%d  broadcast "
        "%d.%d.%d.%d\n",
        en0_addr.u8[3], en0_addr.u8[2], en0_addr.u8[1], en0_addr.u8[0],
        en0_mask.u8[3], en0_mask.u8[2], en0_mask.u8[1], en0_mask.u8[0],
        en0_bcast.u8[3], en0_bcast.u8[2], en0_bcast.u8[1], en0_bcast.u8[0]);

    Stdio.WriteLine(sh,
        "        ether %02x:%02x:%02x:%02x:%02x:%02x  txqueuelen 0  "
        "(Ethernet)\n",
        en0_mac.u8[5], en0_mac.u8[4], en0_mac.u8[3], en0_mac.u8[2], en0_mac.u8[1],
        en0_mac.u8[0]);

    Stdio.WriteLine(sh, "        RX packets %d  bytes %d\n", req->rx_frames,
        req->rx_bytes);

    Stdio.WriteLine(sh, "        RX errors %d  dropped %d  overruns %d  frame %d\n", 0,
        0, 0, 0); // TODO

    Stdio.WriteLine(sh, "        TX packets %d  bytes %d\n", req->tx_frames,
        req->tx_bytes);

    Stdio.WriteLine(sh,
        "        TX errors %d  dropped %d overruns %d  carrier %d  "
        "collisions %d\n",
        0, 0, 0, 0, 0); // TODO

    Stdio.WriteLine(sh, "\n");

    return 0;
}