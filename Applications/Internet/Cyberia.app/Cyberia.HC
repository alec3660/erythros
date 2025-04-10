JsonObject* cyberia = Json.CreateObject(Fs);

Window* win = NULL;
Context2DWidget* controlsbackdrop1 = NULL;
TextLabelWidget* status1 = NULL;
TextLabelWidget* status2 = NULL;
Context2DWidget* statusbackdrop1 = NULL;
VerticalScrollBarWidget* vscroll1 = NULL;

U8* previous_hovered_href = NULL;

ButtonWidget* backbtn1 = NULL;
ButtonWidget* fwdbtn1 = NULL;
ButtonWidget* refreshbtn1 = NULL;
Context2DWidget* background1 = NULL;
TextInputWidget* addressbar1 = NULL;

@window_widgets_list* widgets_base = NULL;
@html_dom_node* node_list = NULL;

I64 old_window_width = -1;
I64 old_window_height = -1;

class @browser
{
    HtmlRenderer* renderer;
    JsonArray* bookmarks;
    JsonArray* history;
    JsonObject* javascript_link_handlers;
    CTask* task;
    U8* fetch_buffer;
    U8* lazyload_buffer;
    U8* lazyload_timeout_buffer;
    U8* go_to_url_string;
    U8* search_query;
};

@browser* browser = CAlloc(sizeof(@browser));
browser->renderer = CAlloc(sizeof(HtmlRenderer));
browser->task = Fs;
browser->history = Json.CreateArray(Fs);
browser->fetch_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE);
browser->go_to_url_string = NULL;
browser->javascript_link_handlers = Json.CreateObject(Fs);
browser->lazyload_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE);
browser->lazyload_timeout_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE);

U0 @cyberia_win_close(Window* win)
{
    // Free everything
    if (win == Compositor.active_win) {
        Gui.Window.SetFocus(Compositor.GetWindowByTitle("Wallpaper"));
    }
    Compositor.UnregisterForGlobalInputEvents(win);
    Compositor.DestroyWindow(win);
}

U8* @browser_tls_connection_state(@http_response* resp)
{
    if (!resp || !resp->s || !resp->s->ctx)
        return NULL;

    I64 connect_state = @tls_connection_status(resp->s->ctx);
    switch (connect_state) {
    case 0:
        return "TLS: Sent Client Hello";
    case 1:
        return "TLS: Parsed Server Hello";
    case 2:
        return "TLS: Key Share";
    case 0xff:
        return "TLS: Finished";
    default:
        return "";
    }
}
extern U0 @cyberia_navigate();

U0 @cyberia_link_clicked(Widget* widget)
{
    @html_dom_node* node = @self_or_ancestor_matches_tag_name(widget->data, "a");
    if (!node)
        return;
    U8* unresolved_href = node->attributes->@("href");
    if (!unresolved_href)
        return;
    U8* resolved_href = @resolve_href(browser->renderer, unresolved_href);
    if (!resolved_href)
        return;
    StrCpy(&addressbar1->text, resolved_href);
    Free(resolved_href);
    Spawn(&@cyberia_navigate);
}

U0 @cyberia_refresh_clicked()
{
    Spawn(&@cyberia_navigate);
}

U0 @cyberia_navigate()
{
    win->focused_widget = NULL;

    if (!StrLen(&addressbar1->text)) {
        return;
    }

    if (MemCmp(&addressbar1->text, "http://", 7) && MemCmp(&addressbar1->text, "https://", 8)) {
        U8 prepend_buf[512];
        StrPrint(prepend_buf, "https://%s", &addressbar1->text);
        StrCpy(&addressbar1->text, prepend_buf);
    }

    U8* url_string = StrNew(&addressbar1->text);
    if (!url_string || !browser || !browser->task)
        return;

    HtmlRenderer* renderer = browser->renderer;
    MemSet(renderer, 0, sizeof(HtmlRenderer));
    widgets_base->next = NULL;
    renderer->images = NULL;
    renderer->link_pointer = Compositor.theme.pointer.link;
    renderer->link_callback = &@cyberia_link_clicked;
    renderer->widgets_base = widgets_base;
    renderer->status_widget = status1;
    renderer->background_widget = background1;
    renderer->vertical_scroll_widget = vscroll1;
    renderer->win = win;

    renderer->current_url_string = StrNew(url_string, browser->task);
    renderer->current_url = @http_parse_url(url_string);
    renderer->cache_directory = HTTP_CACHE_DIRECTORY;
    renderer->task = browser->task;

    U8 err_msg_buffer[128];
    U8 status_text_buffer[1024];

    if (!renderer->current_url) {
        StrCpy(err_msg_buffer, "ERROR: Could not parse URL");
        MessageBox.Error(err_msg_buffer);
        Free(url_string);
        return;
    }

    if (!@is_supported_url_scheme(renderer->current_url)) {
        StrPrint(err_msg_buffer, "ERROR: Unsupported URL scheme: %s", renderer->current_url->scheme);
        MessageBox.Error(err_msg_buffer);
        Free(url_string);
        return;
    }

    HttpUrl* url = renderer->current_url;

    Bool is_alternate_port = FALSE;
    if (!StrICmp(url->scheme, "http://") && url->port != 80)
        is_alternate_port = TRUE;
    if (!StrICmp(url->scheme, "https://") && url->port != 443)
        is_alternate_port = TRUE;
    StrCpy(status_text_buffer, "Fetching ");
    if (is_alternate_port)
        String.Append(status_text_buffer, "%s%s:%d%s%s", url->scheme, url->host, url->port, url->path, url->query);
    else
        String.Append(status_text_buffer, "%s%s%s%s", url->scheme, url->host, url->path, url->query);
    String.Append(status_text_buffer, "...");
    status1->SetText(status_text_buffer);

    U8* buffer = browser->fetch_buffer;
    MemSet(buffer, 0, HTTP_FETCH_BUFFER_SIZE);

    @http_response* resp = Http.Get(renderer->current_url, buffer);
    while (resp->state != HTTP_STATE_DONE) {
        if (resp->state >= HTTP_STATE_HEADERS_RECEIVED) {
            StrPrint(status_text_buffer, "Received %d bytes", resp->body.length);
            status1->SetText(status_text_buffer);
        } else {
            if (@http_scheme_is_https(renderer->current_url)) {
                if (@browser_tls_connection_state(resp)) {
                    StrPrint(status_text_buffer, "%s", @browser_tls_connection_state(resp));
                    status1->SetText(status_text_buffer);
                }
            }
        }
        Sleep(1);
    }

    if (resp->status.code == 301 || resp->status.code == 302) {
        StrCpy(&addressbar1->text, resp->headers->@("Location"));
        @cyberia_navigate;
        return;
    }

    // Create node tree
    I64 images_count = 0;
    node_list = @html_tokenize_and_create_node_list(resp->body.data, resp->body.length, renderer->task, &images_count);

    // Create empty CSS rules array, traverse node tree and populate CSS rules array
    renderer->css_rules = Json.CreateArray(renderer->task);
    renderer->forms = Json.CreateArray(renderer->task);
    @process_css_rules_from_node_list(node_list, renderer);

    //    // Add custom CSS rules
    //    @process_custom_css_rules(renderer);

    // background1->ctx->fill(Color(255, 255, 255));

    status1->SetText("Rendering page...");
    @render_node_list(node_list, renderer);

    @window_widgets_list* append = renderer->widgets_base;
    while (append->next) {
        append = append->next;
    }
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = controlsbackdrop1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = backbtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = fwdbtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = refreshbtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = addressbar1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = statusbackdrop1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = status1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = status2;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list));
    append->next->widget = vscroll1;
    vscroll1->scroll = 0;

    @reflow_node_list(renderer);
    @fetch_images_for_page(renderer);

    status1->SetText("Done");
}

U0 @cyberia_win_keypress(Window* w, I64)
{
    if (w->focused_widget == addressbar1 && KeyDown(SC_ENTER)) {
        Spawn(&@cyberia_navigate);
    }
}

U0 @cyberia_new_tab()
{
    // JsonObject* new_tab = Json.CreateObject(Fs);
    // cyberia->a("tabs")->append(new_tab);
}

U0 @cyberia_win_repaint(Window*)
{
    if (!win || !addressbar1 || !background1 || !vscroll1 || !status1 || !statusbackdrop1)
        return;

    addressbar1->width = win->width - 110;
    background1->width = 0;
    background1->height = 0;
    background1->ctx->width = win->width;
    background1->ctx->height = win->height - 84;

    vscroll1->x = win->width;
    vscroll1->y = background1->y;
    vscroll1->width = 16;
    vscroll1->height = background1->ctx->height;

    if (StrLen(&status2->text)) {
        status1->y = win->height;
        status2->y = win->height - 40;
    } else {
        status1->y = win->height - 40;
        status2->y = win->height;
    }

    statusbackdrop1->y = background1->y + background1->ctx->height;

    if (!browser || !browser->renderer || !widgets_base)
        return;

    if (widgets_base->next && (old_window_width != win->width || old_window_height != win->height)) {
        @reflow_node_list(browser->renderer);
        old_window_width = win->width;
        old_window_height = win->height;
    }

    // vscroll1->length = ToI64(browser->renderer->render_y / vscroll1->height);
    // "render_y: %d\n", browser->renderer->render_y;
    if (browser->renderer->render_y > win->height) {
        vscroll1->x = win->width - 25;
        vscroll1->length = ToI64((vscroll1->height - 32) / (browser->renderer->render_y / (vscroll1->height - 32)));
        //        vscroll1->length = vscroll1->height / (browser->renderer->render_y / vscroll1->height);
    }
}

U0 @cyberia_unset_status_text()
{
    StrCpy(&status2->text, "");
    previous_hovered_href = NULL;
}

U0 @cyberia_win_mouseat(Window*)
{

    if (!win->hovered_widget || !win->hovered_widget->pointer) {
        @cyberia_unset_status_text;
        return;
    }
    @html_dom_node* node = @self_or_ancestor_matches_tag_name(win->hovered_widget->data, "a");
    if (!node)
        return;
    U8* unresolved_href = node->attributes->@("href");
    if (!unresolved_href || previous_hovered_href == unresolved_href)
        return;
    previous_hovered_href = unresolved_href;
    U8* resolved_href = @resolve_href(browser->renderer, unresolved_href);
    if (!resolved_href)
        return;

    StrCpy(&status2->text, resolved_href);
    Free(resolved_href);
}

U0 @cyberia_vscroll_change(Widget*)
{
    if (!browser || !browser->renderer)
        return;

    @reflow_node_list(browser->renderer);
}

U0 @cyberia_init()
{
    win = Compositor.CreateWindow(24, 24, 992, 768, WIN_FLAGS_DEFAULT);
    // win->explicit_repaint = TRUE;
    Gui.Window.SetCallback(win, "close", &@cyberia_win_close);
    Gui.Window.SetCallback(win, "repaint", &@cyberia_win_repaint);
    Gui.Window.SetCallback(win, "mouseat", &@cyberia_win_mouseat);
    Gui.Window.SetIcon(win, Image.FileToContext2D("M:/Applications/Internet/Cyberia.app/lain.png"));
    Gui.Window.Center(win);
    Gui.Window.SetFocus(win);

    controlsbackdrop1 = Gui.CreateWidget(win, WIDGET_TYPE_CONTEXT2D, -14, 0, 0, 0);
    controlsbackdrop1->y = -14;
    controlsbackdrop1->ctx = NewContext2D(Display.Width(), 36 + 14)->fill(Color(204, 204, 204));

    statusbackdrop1 = Gui.CreateWidget(win, WIDGET_TYPE_CONTEXT2D, 0, 0, Display.Width(), 48);
    statusbackdrop1->ctx = NewContext2D(Display.Width(), 48)->fill(Color(204, 204, 204));

    status1 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 0, 0, 320, 16);
    Gui.Widget.SetFont(status1, "Eight Bit Dragon");
    Gui.Widget.SetText(status1, "Idle");

    status2 = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 0, 0, 320, 16);
    Gui.Widget.SetFont(status2, "Eight Bit Dragon");
    Gui.Widget.SetText(status2, "Idle");

    backbtn1 = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, 0, 0, 24, 24);
    Gui.Widget.SetText(backbtn1, "");
    backbtn1->image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/back.png");
    backbtn1->width = backbtn1->image->width + 8;

    fwdbtn1 = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, 33, 0, 24, 24);
    Gui.Widget.SetText(fwdbtn1, "");
    fwdbtn1->image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/forward.png");
    fwdbtn1->width = fwdbtn1->image->width + 8;

    refreshbtn1 = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, 66, 0, 24, 24);
    Gui.Widget.SetText(refreshbtn1, "");
    Gui.Widget.SetCallback(refreshbtn1, "clicked", &@cyberia_refresh_clicked);
    refreshbtn1->image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/reload.png");
    refreshbtn1->width = refreshbtn1->image->width + 8;

    background1 = Gui.CreateWidget(win, WIDGET_TYPE_CONTEXT2D, 0, 36, 0, 0);
    background1->ctx = NewContext2D(Display.Width(), Display.Height());
    background1->ctx->fill(Color(255, 255, 255));

    vscroll1 = Gui.CreateWidget(win, WIDGET_TYPE_VERT_SCROLLBAR, -99999, -99999, 0, 0);
    Gui.Widget.SetCallback(vscroll1, "change", &@cyberia_vscroll_change);

    addressbar1 = Gui.CreateWidget(win, WIDGET_TYPE_INPUT, 99, 6, 320, 16);
    Gui.Widget.SetFont(addressbar1, "Eight Bit Dragon");
    Gui.Window.SetCallback(win, "keypress", &@cyberia_win_keypress);
    widgets_base = win->widget;

    while (widgets_base->next) {
        widgets_base = widgets_base->next;
    }

    win->focused_widget = addressbar1;
    @cyberia_win_repaint(win);
}

@cyberia_init;

U0 Main()
{
    while (1)
        Sleep(1);
}

Main;
