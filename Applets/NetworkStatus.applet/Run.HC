Gui.App();

U64 flags = WIN_FLAGS_MOVABLE | WIN_FLAGS_ICON | WIN_FLAGS_TITLE_BAR | WIN_FLAGS_CLOSE_BUTTON | WIN_FLAGS_SKIP;
Window* win = Compositor.CreateWindow(Display.Width() - 240, 33, 240, 120, flags);
Gui.Window.SetIcon(win, Image.FileToContext2D("window_icon_16x16.png"));
Gui.Window.Hide(win);
Gui.Window.SetTitle(win, "Network Status");

TextLabelWidget* status_label1 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 16, 16, 192, 16);
TextLabelWidget* status_label2 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 16, 32, 192, 16);
TextLabelWidget* status_label3 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 16, 48, 192, 16);
TextLabelWidget* status_label4 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 16, 64, 192, 16);

TextLabelWidget* status_label5 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 128, 16, 192, 16);
TextLabelWidget* status_label6 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 128, 32, 192, 16);
TextLabelWidget* status_label7 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 128, 48, 192, 16);
TextLabelWidget* status_label8 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 128, 64, 192, 16);
Gui.Widget.SetFont(status_label1, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label2, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label3, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label4, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label5, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label6, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label7, "Eight Bit Dragon");
Gui.Widget.SetFont(status_label8, "Eight Bit Dragon");

Context2DWidget* network_icon = SystemTray.RegisterItem();

Context2D* ctx_network_error = Image.FileToContext2D("M:/Media/Themes/Umami/Icon/status/network-error.png");
Context2D* ctx_network_idle = Image.FileToContext2D("M:/Media/Themes/Umami/Icon/status/network-idle.png");
Context2D* ctx_network_offline = Image.FileToContext2D(
    "M:/Media/Themes/Umami/Icon/status/network-offline.png");
Context2D* ctx_network_rx = Image.FileToContext2D(
    "M:/Media/Themes/Umami/Icon/status/network-receive.png");
Context2D* ctx_network_tx = Image.FileToContext2D(
    "M:/Media/Themes/Umami/Icon/status/network-transmit.png");
Context2D* ctx_network_txrx = Image.FileToContext2D(
    "M:/Media/Themes/Umami/Icon/status/network-transmit-receive.png");
Context2D* ctx_network_wireless_enc = Image.FileToContext2D(
    "M:/Media/Themes/Umami/Icon/status/network-wireless-encrypted.png");

U0 @networkstatus_show(Widget*)
{

    NetInfoRequest* req = @net_info_request;

    win->flags &= ~WIN_FLAGS_SKIP;

    U8 status_ipaddr[128];
    U8 status_netmask[128];
    U8 status_gateway[128];
    U8 status_dns1[128];

    StrPrint(&status_ipaddr, "%d.%d.%d.%d", req->ipv4_address.u8[3], req->ipv4_address.u8[2],
        req->ipv4_address.u8[1], req->ipv4_address.u8[0]);
    StrPrint(&status_netmask, "%d.%d.%d.%d", req->ipv4_netmask.u8[3], req->ipv4_netmask.u8[2],
        req->ipv4_netmask.u8[1], req->ipv4_netmask.u8[0]);
    StrPrint(&status_gateway, "%d.%d.%d.%d", req->ipv4_gateway.u8[3], req->ipv4_gateway.u8[2],
        req->ipv4_gateway.u8[1], req->ipv4_gateway.u8[0]);
    StrPrint(&status_dns1, "%d.%d.%d.%d", req->dns_server_address.u8[3], req->dns_server_address.u8[2],
        req->dns_server_address.u8[1], req->dns_server_address.u8[0], req->dns_server_port);

    Gui.Widget.SetText(status_label1, "IP address:");
    Gui.Widget.SetText(status_label2, "Subnet mask:");
    Gui.Widget.SetText(status_label3, "Gateway:");
    Gui.Widget.SetText(status_label4, "DNS Server:");

    Gui.Widget.SetText(status_label5, &status_ipaddr);
    Gui.Widget.SetText(status_label6, &status_netmask);
    Gui.Widget.SetText(status_label7, &status_gateway);
    Gui.Widget.SetText(status_label8, &status_dns1);

    Gui.Window.SetFocus(win);
    Gui.Window.Refresh(win);
    while (!Gui.Window.IsVisible(win))
        Compositor.ShowWindow(win);
}

U0 @networkstatus_hide(Window*)
{
    win->flags |= WIN_FLAGS_SKIP;
    Compositor.HideWindow(win);
}

network_icon->ctx = ctx_network_error;
Gui.Window.Refresh(Compositor.menubar.win);
Gui.Window.SetCallback(win, "close", &@networkstatus_hide);

U0 Main()
{
    Gui.Widget.SetCallback(network_icon, "clicked", &@networkstatus_show);
    while (1) {
        if (network_icon->ctx == ctx_network_error) {
            network_icon->ctx = ctx_network_idle;
            Gui.Window.Refresh(Compositor.menubar.win);
        }
        Sleep(10);
    }
}

Main;
