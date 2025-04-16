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
ButtonWidget* hanbagabtn1 = NULL;
Context2DWidget* background1 = NULL;
TextInputWidget* addressbar1 = NULL;

@window_widgets_list* widgets_base = NULL;
@html_dom_node* node_list = NULL;

I64 old_window_width = -1;
I64 old_window_height = -1;
I64 old_mouse_z = Mouse.z;

Window* hanbaga_menu = Menu.New("Cyberia");
Menu.AddItem(hanbaga_menu, "New Tab", NULL, &Reboot, NULL, NULL);
Menu.AddItem(hanbaga_menu, "New Window", NULL, NULL, NULL, NULL);
Menu.AddItem(hanbaga_menu, "New Private Window", NULL, NULL, NULL, NULL);

class @browser
{
    HtmlRenderer* renderer;
    JsonArray* bookmarks;
    JsonArray* history;
    I64 history_index;
    JsonObject* javascript_link_handlers;
    CTask* task;
    U8* fetch_buffer;
    U8* lazyload_buffer;
    U8* lazyload_timeout_buffer;
    U8* go_to_url_string;
    U8* search_query;
};

@browser* browser = CAlloc(sizeof(@browser), Fs);

I64 @cyberia_is_alphanum(I64 c)
{
    return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9');
}

U8* @cyberia_urlencode_str(U8* str, I64* output_len)
{
    if (str == NULL) {
        return NULL;
    }

    I64 len = StrLen(str);
    U8* encoded_str = NULL;
    U8* dest;
    I64 encoded_len = 0;
    U8* p;
    I64 c;
    Bool contains_plus = FALSE;

    // First pass: calculate the exact required length
    p = str;
    while (*p) {
        c = *p;
        // Check if the character should NOT be encoded
        if (@cyberia_is_alphanum(c) || c == '-' || c == '_' || c == '.') {
            encoded_len++;
        } else if (c == ' ') {
            encoded_len++; // Will be replaced by '+'
            contains_plus = TRUE;
        } else {
            encoded_len += 3; // Will be replaced by %XX
        }
        ++p;
    }

    *output_len = encoded_len;

    if (encoded_len == StrLen(str) && !contains_plus)
        return str;

    // Allocate memory for the encoded string + null terminator
    encoded_str = CAlloc(encoded_len + 1, browser->task);
    if (!encoded_str)
        return NULL;

    // Second pass: build the encoded string
    dest = encoded_str;
    p = str;
    while (*p) {
        c = *p;
        if (@cyberia_is_alphanum(c) || c == '-' || c == '_' || c == '.') {
            *dest++ = c;
        } else if (c == ' ') {
            *dest++ = '+';
        } else {
            StrPrint(dest, "%%%02X", c);
            dest += 3;
        }
        ++p;
    }
    *dest = '\0';
    return encoded_str;
}

browser->history = Json.CreateArray(Fs);
browser->history_index = -1;
browser->renderer = NULL;
browser->task = Fs;
browser->fetch_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, browser->task);
browser->go_to_url_string = NULL;
browser->javascript_link_handlers = Json.CreateObject(Fs);
browser->lazyload_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, browser->task);
browser->lazyload_timeout_buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, browser->task);

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
extern U0 @cyberia_navigate(Bool refresh = FALSE);

U0 @cyberia_hanbaga_show(Widget* widget)
{
    hanbaga_menu->x = win->x + win->width - hanbaga_menu->width - 5;
    hanbaga_menu->y = win->y + hanbagabtn1->y + hanbagabtn1->height + 24;
    Gui.Window.Show(hanbaga_menu);
    Gui.Window.SetFocus(hanbaga_menu);
    Gui.Window.Refresh(hanbaga_menu);
}

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

U0 @cyberia_collect_form_nodes(JsonArray* array, @html_dom_node* node)
{
    if (!array || !node)
        return;

    if (!StrICmp(node->tagName, "input") || !StrICmp(node->tagName, "textarea")) {
        if (node->attributes->@("name")) {
            array->append(node, JSON_NUMBER);
        }
    }

    I64 i;
    if (node->children->length) {
        for (i = 0; i < node->children->length; i++)
            @cyberia_collect_form_nodes(array, node->children->@(i));
    }
}

I64 @cyberia_count_text_input_elements(@html_dom_node* node)
{
    I64 count = 0;
    if (!node)
        return count;

    if (!StrICmp(node->tagName, "input") && (!node->attributes->@("type") || (!StrICmp(node->attributes->@("type"), "text") || !StrICmp(node->attributes->@("type"), "password"))))
        ++count;

    I64 i;
    if (node->children->length) {
        for (i = 0; i < node->children->length; i++)
            count += @cyberia_count_text_input_elements(node->children->@(i));
    }
    return count;
}

Bool @cyberia_form_has_one_text_input_element(@html_dom_node* form_node)
{
    return @cyberia_count_text_input_elements(form_node);
}

U0 @cyberia_form_submit(@html_dom_node* form_node)
{
    if (!form_node->attributes->@("method"))
        form_node->attributes->set("method", "get", JSON_STRING);

    if (!form_node->attributes->@("action"))
        form_node->attributes->set("action", "#", JSON_STRING);

    I64 i;
    U8* method = form_node->attributes->@("method");
    U8* action = @resolve_href(browser->renderer, form_node->attributes->@("action"));
    @html_dom_node* element_node;

    JsonArray* form_elements = Json.CreateArray(browser->renderer->task);
    @cyberia_collect_form_nodes(form_elements, form_node);

    U8 get_request_str[1024];

    if (!StrICmp(method, "get")) {
        StrPrint(get_request_str, "%s?", action);
        for (i = 0; i < form_elements->length; i++) {
            element_node = form_elements->@(i);
            U8* name = element_node->attributes->@("name");
            U8* raw_value = "";
            U8* encoded_value = NULL;
            I64 encoded_value_length = 0;
            Widget* element_gui_widget = element_node->attributes->@("cyberiaGuiWidget");
            switch (element_gui_widget->type) {
            case WIDGET_TYPE_CHECKBOX:
                if (element_gui_widget(CheckBoxWidget*)->checked) {
                    raw_value = @t(element_node->attributes->@("value"), element_node->attributes->@("value"), "on");
                } else {
                    raw_value = NULL;
                }
                break;
            case WIDGET_TYPE_INPUT:
                raw_value = &element_gui_widget(TextInputWidget*)->text;
                break;
            default:
                break;
            }

            encoded_value = @cyberia_urlencode_str(raw_value, &encoded_value_length);

            if (encoded_value) {
                String.Append(get_request_str, "%s=%s", name, encoded_value);
                if (i < form_elements->length - 1)
                    String.Append(get_request_str, "&");
                if (encoded_value_length != StrLen(raw_value)) {
                    Free(encoded_value);
                }
            }
        }
        StrCpy(&addressbar1->text, &get_request_str);
    }

    Free(action);
    Spawn(&@cyberia_navigate);
}

U0 @cyberia_form_submit_clicked(Widget* widget)
{
    if (!widget || !widget->data)
        return;

    @html_dom_node* form_node = @self_or_ancestor_matches_tag_name(widget->data, "form");

    if (!form_node)
        return;

    @cyberia_form_submit(form_node);
}

U0 @cyberia_refresh_clicked()
{
    if (refreshbtn1->disabled)
        return;
    Spawn(&@cyberia_navigate, TRUE);
}

U0 @cyberia_update_history_buttons()
{
    backbtn1->disabled = TRUE;
    fwdbtn1->disabled = TRUE;
    if (browser->history_index > 0)
        backbtn1->disabled = FALSE;
    if (browser->history->length - 1 > browser->history_index)
        fwdbtn1->disabled = FALSE;
}

U0 @cyberia_history()
{
    win->focused_widget = NULL;

    HtmlRenderer* renderer = browser->renderer = browser->history->@(browser->history_index);

    HttpUrl* url = renderer->current_url;
    StrCpy(&addressbar1->text, "");

    Bool is_alternate_port = FALSE;
    if (!StrICmp(url->scheme, "http://") && url->port != 80)
        is_alternate_port = TRUE;
    if (!StrICmp(url->scheme, "https://") && url->port != 443)
        is_alternate_port = TRUE;
    if (is_alternate_port)
        String.Append(&addressbar1->text, "%s%s:%d%s%s", url->scheme, url->host, url->port, url->path, url->query);
    else
        String.Append(&addressbar1->text, "%s%s%s%s", url->scheme, url->host, url->path, url->query);

    renderer->background_widget->ctx = renderer->background_ctx;
    renderer->background_widget->ctx->width = Display.Width();
    renderer->background_widget->ctx->height = Display.Height();

    Gui.Window.SetTitle(renderer->win, renderer->current_title);

    widgets_base->next = renderer->widgets_base;

    @reflow_node_list(renderer);
    Gui.Window.SetIcon(win, @favicon_for_page(renderer));

    status1->SetText("Done");
    refreshbtn1->disabled = FALSE;
}

U0 @cyberia_back_clicked()
{
    if (backbtn1->disabled)
        return;
    if (browser->history_index > 0) {
        --browser->history_index;
        @cyberia_update_history_buttons;
        @cyberia_history;
    }
}

U0 @cyberia_fwd_clicked()
{
    if (fwdbtn1->disabled)
        return;
    if (browser->history_index < browser->history->length - 1) {
        ++browser->history_index;
        @cyberia_update_history_buttons;
        @cyberia_history;
    }
}

U0 @cyberia_navigate(Bool refresh = FALSE)
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

    if (!refresh) {
        browser->renderer = CAlloc(sizeof(HtmlRenderer), browser->task);
        ++browser->history_index;
        while (browser->history->@(browser->history_index)) {
            browser->history->remove(browser->history_index);
        }
        browser->history->append(browser->renderer, JSON_NUMBER);
        @cyberia_update_history_buttons;
    }

    HtmlRenderer* renderer = browser->renderer;
    MemSet(renderer, 0, sizeof(HtmlRenderer));
    widgets_base->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    renderer->images = NULL;
    renderer->link_pointer = Compositor.theme.pointer.link;
    renderer->link_callback = &@cyberia_link_clicked;
    renderer->form_submit_callback = &@cyberia_form_submit_clicked;
    renderer->widgets_base = widgets_base->next;
    renderer->status_widget = status1;
    renderer->background_widget = background1;
    renderer->background_ctx = NewContext2D(Display.Width(), Display.Height())->fill(Color(255, 255, 255));
    renderer->background_widget->ctx = renderer->background_ctx;
    renderer->background_widget->ctx->width = Display.Width();
    renderer->background_widget->ctx->height = Display.Height();

    renderer->vertical_scroll_widget = vscroll1;
    renderer->win = win;
    renderer->indent = -1;

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
        U8* unresolved_location = resp->headers->@("Location");
        if (!unresolved_location)
            return;
        U8* resolved_location = @resolve_href(browser->renderer, unresolved_location);
        if (!resolved_location)
            return;
        StrCpy(&addressbar1->text, resolved_location);
        Free(resolved_location);
        @cyberia_navigate(1);
        return;
    }

    // Create node tree
    I64 images_count = 0;
    node_list = @html_tokenize_and_create_node_list(resp->body.data, resp->body.length, renderer->task, &images_count);

    // Create empty CSS rules array, traverse node tree and populate CSS rules array
    renderer->css_rules = Json.Clone(CSS_DEFAULT_RULES, renderer->task);
    renderer->forms = Json.CreateArray(renderer->task);
    @process_css_rules_from_node_list(node_list, renderer);

    status1->SetText("Rendering page...");
    Sleep(100);
    @render_node_list(node_list, renderer);

    @window_widgets_list* append = renderer->widgets_base;
    while (append->next) {
        append = append->next;
    }
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = controlsbackdrop1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = backbtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = fwdbtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = refreshbtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = hanbagabtn1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = addressbar1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = statusbackdrop1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = status1;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = status2;
    append = append->next;
    append->next = CAlloc(sizeof(@window_widgets_list), browser->task);
    append->next->widget = vscroll1;
    vscroll1->scroll = 0;

    @reflow_node_list(renderer);
    Gui.Window.SetIcon(win, @favicon_for_page(renderer));
    @fetch_images_for_page(renderer);

    status1->SetText("Done");
    refreshbtn1->disabled = FALSE;
}

U0 @cyberia_win_keypress(Window* w, I64)
{
    if (!w || !w->focused_widget || !KeyDown(SC_ENTER))
        return;

    if (w->focused_widget == addressbar1) {
        Spawn(&@cyberia_navigate);
        return;
    }

    @html_dom_node* node = w->focused_widget->data;

    if (!node)
        return;
    if (StrICmp(node->tagName, "input"))
        return;
    if (node->attributes->@("type") && (StrICmp(node->attributes->@("type"), "text") && StrICmp(node->attributes->@("type"), "password")))
        return;

    @html_dom_node* form_node = @self_or_ancestor_matches_tag_name(node, "form");
    if (!form_node)
        return;

    // If we are the only text input element, submit the form
    if (@cyberia_form_has_one_text_input_element(form_node)) {
        @cyberia_form_submit(form_node);
    }
}

U0 @cyberia_new_tab()
{
    // JsonObject* new_tab = Json.CreateObject(Fs);
    // cyberia->a("tabs")->append(new_tab);
}

U0 @cyberia_vscroll_change(Widget*)
{
    if (!browser || !browser->renderer)
        return;

    @reflow_node_list(browser->renderer);
}

U0 @cyberia_win_repaint(Window*)
{
    if (!win || !addressbar1 || !background1 || !vscroll1 || !status1 || !statusbackdrop1)
        return;

    hanbagabtn1->x = win->width - hanbagabtn1->width - 9;
    addressbar1->width = hanbagabtn1->x - addressbar1->x - 3;
    background1->width = 0;
    background1->height = 0;
    background1->ctx->width = win->width;
    background1->ctx->height = win->height - 84;

    vscroll1->x = win->width;
    vscroll1->y = background1->y;
    vscroll1->width = 16;
    vscroll1->height = background1->ctx->height;

    I64 delta_z = Mouse.z - old_mouse_z;
    if (delta_z) {
        vscroll1->scroll += (RENDERER_DEFAULT_MAX_LINE_HEIGHT * delta_z);
        @cyberia_vscroll_change(vscroll1);
    }
    old_mouse_z = Mouse.z;

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

    if (browser->renderer->calculated_page_height > background1->ctx->height) {
        vscroll1->max = browser->renderer->calculated_page_height;
        vscroll1->length = (vscroll1->height - 31) / MaxI64(2, ToI64(browser->renderer->calculated_page_height / background1->ctx->height));
        vscroll1->x = win->width - 25;
    }
}

U0 @cyberia_unset_status_text()
{
    StrCpy(&status2->text, "");
    previous_hovered_href = NULL;
}

U0 @cyberia_addressbar_clicked(Widget*)
{
    if (StrLen(&addressbar1->text) && addressbar1->selected_region_start == -1 && addressbar1->selected_region_end == -1) {
        addressbar1->selected_region_start = 0;
        addressbar1->selected_region_end = StrLen(&addressbar1->text) - 1;
    }
}

U0 @cyberia_win_mouseat(Window*)
{
    if (addressbar1 && win->focused_widget != addressbar1) {
        addressbar1->selected_region_start = -1;
        addressbar1->selected_region_end = -1;
    }

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

U0 @cyberia_init()
{
    win = Compositor.CreateWindow(24, 24, 992, 768, WIN_FLAGS_DEFAULT);
    // win->explicit_repaint = TRUE;
    Gui.Window.SetCallback(win, "close", &@cyberia_win_close);
    Gui.Window.SetCallback(win, "repaint", &@cyberia_win_repaint);
    Gui.Window.SetCallback(win, "mouseat", &@cyberia_win_mouseat);
    Gui.Window.SetIcon(win, DEFAULT_FAVICON);
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
    Gui.Widget.SetCallback(backbtn1, "clicked", &@cyberia_back_clicked);
    backbtn1->image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/back.png");
    backbtn1->disabled_image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/back-disabled.png");
    backbtn1->disabled = TRUE;
    backbtn1->width = backbtn1->image->width + 8;

    fwdbtn1 = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, 33, 0, 24, 24);
    Gui.Widget.SetText(fwdbtn1, "");
    Gui.Widget.SetCallback(fwdbtn1, "clicked", &@cyberia_fwd_clicked);
    fwdbtn1->image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/forward.png");
    fwdbtn1->disabled_image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/forward-disabled.png");
    fwdbtn1->disabled = TRUE;
    fwdbtn1->width = fwdbtn1->image->width + 8;

    refreshbtn1 = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, 66, 0, 24, 24);
    Gui.Widget.SetText(refreshbtn1, "");
    Gui.Widget.SetCallback(refreshbtn1, "clicked", &@cyberia_refresh_clicked);
    refreshbtn1->image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/reload.png");
    refreshbtn1->disabled_image = @image_file_to_context2d("M:/Media/Themes/Umami/Icon/actions/reload-disabled.png");
    refreshbtn1->disabled = TRUE;
    refreshbtn1->width = refreshbtn1->image->width + 8;

    hanbagabtn1 = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, U64_MAX, 0, 24, 24);
    Gui.Widget.SetText(hanbagabtn1, "");
    Gui.Widget.SetCallback(hanbagabtn1, "clicked", &@cyberia_hanbaga_show);
    hanbagabtn1->image = @image_file_to_context2d("M:/Applications/Internet/Cyberia.app/Resources/hanbaga.png");
    hanbagabtn1->width = hanbagabtn1->image->width + 8;

    background1 = Gui.CreateWidget(win, WIDGET_TYPE_CONTEXT2D, 0, 36, 0, 0);
    background1->ctx = NewContext2D(Display.Width(), Display.Height());
    background1->ctx->fill(Color(255, 255, 255));

    vscroll1 = Gui.CreateWidget(win, WIDGET_TYPE_VERT_SCROLLBAR, -99999, -99999, 0, 0);
    Gui.Widget.SetCallback(vscroll1, "change", &@cyberia_vscroll_change);

    addressbar1 = Gui.CreateWidget(win, WIDGET_TYPE_INPUT, 100, 6, 320, 16);
    Gui.Widget.SetFont(addressbar1, "Eight Bit Dragon");
    Gui.Widget.SetCallback(addressbar1, "clicked", &@cyberia_addressbar_clicked);
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
    while (1) {
        if (Compositor.active_win != hanbaga_menu && Gui.Window.IsVisible(hanbaga_menu))
            Gui.Window.Hide(hanbaga_menu);
        Sleep(1);
    }
}

Main;
