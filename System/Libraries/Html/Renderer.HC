#define RENDERER_DEFAULT_MAX_LINE_HEIGHT 8

class @html_lazyload_image
{
    HttpUrl* url;
    @http_request* req;
    @http_response* resp;
    I64 index;
    I64 jiffies;
    @html_lazyload_image* next;
};

class @html_renderer
{
    CTask* task;
    HttpUrl* current_url;
    JsonArray* css_rules;
    JsonArray* forms;
    U8* cache_directory;
    U8* current_title;
    U8* current_url_string;
    I64 forms_index;
    @image_collection* img_coll;
    I64 img_count;
    Bool last_char_was_whitespace;
    Bool enable_animations;
    Bool enable_lazy_loading;
    U8 status_text[128];
    VerticalScrollBarWidget* vertical_scroll_widget;
    TextLabelWidget* status_widget;
    Context2DWidget* background_widget;
    Window* win;
    @window_widgets_list* widgets_base;
    @window_widgets_list* images;
    I64 render_x;
    I64 render_y;
    I64 max_line_height;
    Context2D* link_pointer;
    U64 link_callback;
};

#define HtmlRenderer @html_renderer

#define HTML_WORK_BUFFER_SIZE 2048

U0 @html_renderer_update_status_text(HtmlRenderer* renderer, U8* text)
{
    U8 buf[128];
    if (!renderer || !text)
        return;
    if (StrLen(text) < 128)
        Gui.Widget.SetText(renderer->status_widget, text);
    else {
        MemSet(buf, NULL, 128);
        MemCpy(buf, text, 127);
        Gui.Widget.SetText(renderer->status_widget, buf);
    }
}

U0(*@html_follow_link_fp)
(HtmlRenderer* renderer, U8* url_string) = NULL;

U8* @sanitize_node_text(HtmlRenderer* renderer, U8* text)
{
    if (!renderer || !text || !StrLen(text))
        return "";
    U8* original_text = text;
    U8* ch = text;
    Bool needs_sanitization = FALSE;
    while (*ch && !needs_sanitization) {
        switch (*ch) {
        case 0x11:
        case 0x12:
        case 0x24:
            needs_sanitization = TRUE;
            break;
        default:
            break;
        }
        *ch++;
    }
    if (!needs_sanitization)
        return text;
    while (*text == ' ')
        text++;
    while (text[StrLen(text) - 1] == ' ')
        text[StrLen(text) - 1] = NULL;
    while (StrFind("  ", text))
        StrCpy(StrFind("  ", text), StrFind("  ", text) + 1);
    U8* new_text = CAlloc(StrLen(text) * 2, renderer->task);
    I64 i = 0;
    while (i < StrLen(text)) {
        switch (text[i]) {
        case 0x11:
            StrCpy(new_text + StrLen(new_text), "&");
            i++;
            break;
        case 0x12:
            StrCpy(new_text + StrLen(new_text), "<");
            i++;
            break;
        case 0x24:
            StrCpy(new_text + StrLen(new_text), "\d");
            i++;
            break;
        default:
            StrPrint(new_text + StrLen(new_text), "%c", text[i]);
            i++;
            break;
        }
    }
    Free(original_text);
    return new_text;
}

Bool @is_supported_url_scheme(@http_url* url)
{
    return @t(!StrICmp(url->scheme, "http://") || !StrICmp(url->scheme, "https://"), TRUE, FALSE);
}

HttpUrl* @expand_url_from_string(CTask* task, HttpUrl* current_url, U8* str)
{
    U8 buf[HTML_WORK_BUFFER_SIZE];
    HttpUrl* url = @http_parse_url(str);

    // First, check if the parsed URL is a supported scheme.
    if (@is_supported_url_scheme(url))
        return url;
    else {
        if (url->scheme[0] == '/' && url->scheme[1] == '/') {
            // This is most likely a protocol agnostic URL, let's try to parse it:
            StrPrint(buf, "%s%s", current_url->scheme, str + 2);
            @http_free_url(url);
            return @http_parse_url(buf);
        }

        Bool is_alternate_port = FALSE;
        if (!StrICmp(current_url->scheme, "http://") && current_url->port != 80)
            is_alternate_port = TRUE;
        if (!StrICmp(current_url->scheme, "https://") && current_url->port != 443)
            is_alternate_port = TRUE;

        if (str[0] == '/' && str[1] != '/' && str[1]) {
            // This is most likely a relative URL, let's try to parse it:
            if (is_alternate_port)
                StrPrint(buf, "%s%s:%d%s", current_url->scheme,
                    current_url->host, current_url->port, str);
            else
                StrPrint(buf, "%s%s%s", current_url->scheme,
                    current_url->host, str);
            @http_free_url(url);
            return @http_parse_url(buf);
        }

        U8 resolved_relative_path[HTML_WORK_BUFFER_SIZE];
        StrCpy(resolved_relative_path, current_url->path);
        MemSet(StrLastOcc(resolved_relative_path, "/") + 1, NULL, 1);

        // This could still be a relative URL, let's try to parse it:
        if (is_alternate_port)
            StrPrint(buf, "%s%s:%d%s%s", current_url->scheme,
                current_url->host, current_url->port, resolved_relative_path, str);
        else
            StrPrint(buf, "%s%s%s%s", current_url->scheme,
                current_url->host, resolved_relative_path, str);
        @http_free_url(url);
        return @http_parse_url(buf);
    }
}

U8* @resolve_href(HtmlRenderer* renderer, U8* href)
{
    if (!renderer || !href)
        return NULL;
    if (!MemCmp(href, "javascript:", 11))
        return href;
    HttpUrl* url = @expand_url_from_string(renderer->task, renderer->current_url, href);
    if (!url)
        return NULL;
    U8* resolved_href = CAlloc(HTML_WORK_BUFFER_SIZE, renderer->task);
    Bool is_alternate_port = FALSE;
    if (!StrICmp(url->scheme, "http://") && url->port != 80)
        is_alternate_port = TRUE;
    if (!StrICmp(url->scheme, "https://") && url->port != 443)
        is_alternate_port = TRUE;
    if (is_alternate_port)
        StrPrint(resolved_href, "%s%s:%d%s%s", url->scheme, url->host, url->port, url->path, url->query);
    else
        StrPrint(resolved_href, "%s%s%s%s", url->scheme, url->host, url->path, url->query);
    @http_free_url(url);
    return resolved_href;
}

I64 @css_resolve_byte_from_hex(U8* ch, Bool skip_increment = FALSE)
{
    I64 res = 0;
    I64 b = ToUpper(*ch);
    if (b < 'A') {
        res += (b - '0') << 4;
    } else {
        res += (10 + (b - 'A')) << 4;
    }
    if (!skip_increment) {
        ++ch;
        b = ToUpper(*ch);
    }
    if (b < 'A') {
        res += (b - '0');
    } else {
        res += (10 + (b - 'A'));
    }
    return res;
}

U32 @css_resolve_color_from_rrggbb(U8* str)
{
    *str++;
    switch (StrLen(str)) {
    case 6:
        return Color(@css_resolve_byte_from_hex(str), @css_resolve_byte_from_hex(str + 2), @css_resolve_byte_from_hex(str + 4));
    case 3:
        return Color(@css_resolve_byte_from_hex(str, 1), @css_resolve_byte_from_hex(str + 1, 1), @css_resolve_byte_from_hex(str + 2, 1));
    default:
        return 0;
    }
}

Bool @render_css_for_node(@html_dom_node* node, HtmlRenderer* renderer)
{
    I64 i, j, k;
    JsonObject* rule = NULL;
    JsonArray* matches = NULL;
    JsonObject* properties = NULL;
    JsonKey* key = NULL;
    JsonArray* values = NULL;
    U8* selector = NULL;
    Bool matched = FALSE;
    Bool should_display = TRUE;
    U8 node_classes_buffer[HTML_WORK_BUFFER_SIZE];
    U8 prepend_buffer[64];
    U8 append_buffer[64];
    MemSet(prepend_buffer, 0, 64);
    MemSet(append_buffer, 0, 64);
    U8 node_tmpnum_buf[16];
    U8** node_classes;
    I64 node_classes_count = 0;
    I64 color = TRANSPARENT;
    U8 node_ptr_string[32];
    U8* tmpmd5;

    for (i = 0; i < renderer->css_rules->length; i++) {
        rule = renderer->css_rules->@(i);
        matched = FALSE;
        if (rule->@("matches")) {

            matches = rule->@("matches");
            properties = rule->@("properties");

            // check if node md5 hash matches
            if (*(matches->@(0)(U8*)) == 0xFE) {
                StrPrint(node_ptr_string, "0x%08x", node);
                tmpmd5 = md5_string(node_ptr_string, StrLen(node_ptr_string));
                if (!StrCmp(matches->@(0) + 1, tmpmd5)) {
                    matched = TRUE;
                    Free(tmpmd5);
                    goto @css_rule_check_if_matched;
                }
                Free(tmpmd5);
            }

            // try to match tagName
            if (!StrICmp(matches->@(0), node->tagName)) {
                matched = TRUE;
                goto @css_rule_check_if_matched;
            }

            // try to match id
            if (*(matches->@(0)(U8*)) == '#' && node->attributes->@("id")) {
                if (!StrCmp(matches->@(0) + 1, node->attributes->@("id"))) {
                    matched = TRUE;
                    goto @css_rule_check_if_matched;
                }
            }

            // try to match selectors
            for (j = 0; j < matches->length; j++) {
                selector = matches->@(j);

                if (node->attributes->@("class") && StrFirstOcc(selector, ".")) {
                    // node has class attribute and current selector has .class

                    if (!StrFirstOcc(node->attributes->@("class"), " ")) {
                        if (!StrCmp(node->attributes->@("class"), StrFirstOcc(selector, ".") + 1)) {
                            matched = TRUE;
                            goto @css_rule_check_if_matched;
                        }
                    } else {
                        MemSet(node_classes_buffer, 0, HTML_WORK_BUFFER_SIZE);
                        StrCpy(node_classes_buffer, node->attributes->@("class"));
                        node_classes = String.Split(node_classes_buffer, ' ', &node_classes_count);

                        for (k = 0; k < node_classes_count; k++) {
                            if (!StrCmp(node_classes[k], StrFirstOcc(selector, ".") + 1)) {
                                matched = TRUE;
                                Free(node_classes);
                                goto @css_rule_check_if_matched;
                            }
                        }
                    }
                }
            }

            @css_rule_check_if_matched : if (matched)
            {
                key = properties->keys;
                for (j = 0; j < properties->length; j++) {
                    values = properties->@(key->name);

                    if (!StrICmp(key->name, "display") && !StrICmp(values->@(0), "none"))
                        return FALSE;

                    if (!StrICmp(key->name, "background") || !StrICmp(key->name, "background-color")) {
                        if (@css_named_colors->@(values->@(0))) {
                            node->backgroundColor = @css_resolve_color_from_rrggbb(@css_named_colors->@(values->@(0)));
                        } else if (values->@(0)(U8*)[0] == '#') {
                            node->backgroundColor = @css_resolve_color_from_rrggbb(values->@(0));
                        } else {
                            // unsupported
                        }
                    }

                    if (!StrICmp(key->name, "color")) {
                        if (@css_named_colors->@(values->@(0))) {
                            node->color = @css_resolve_color_from_rrggbb(@css_named_colors->@(values->@(0)));
                        } else if (values->@(0)(U8*)[0] == '#') {
                            node->color = @css_resolve_color_from_rrggbb(values->@(0));
                        } else {
                            // unsupported
                        }
                    }

                    if (!StrICmp(key->name, "width") && !StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "px")) {
                        StrCpy(node_tmpnum_buf, values->@(0));
                        node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                        node->width = Str2I64(node_tmpnum_buf);
                    }

                    if (!StrICmp(key->name, "height") && !StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "px")) {
                        StrCpy(node_tmpnum_buf, values->@(0));
                        node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                        node->height = Str2I64(node_tmpnum_buf);
                    }

                    if (!StrICmp(key->name, "text-align") && !StrICmp(values->@(0), "center"))
                        node->textAlign = CSS_TEXT_ALIGN_CENTER;
                    if (!StrICmp(key->name, "text-align") && !StrICmp(values->@(0), "right"))
                        node->textAlign = CSS_TEXT_ALIGN_RIGHT;

                    if (!StrICmp(key->name, "line-height") && !StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "px")) {
                        StrCpy(node_tmpnum_buf, values->@(0));
                        node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                        node->font_size = ToI64((Str2I64(node_tmpnum_buf) / 3) * 2);
                    }

                    if (!StrICmp(key->name, "font-size") && !StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "px")) {
                        StrCpy(node_tmpnum_buf, values->@(0));
                        node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                        node->font_size = Str2I64(node_tmpnum_buf);
                    }

                    key = key->next;
                }
            }
        }
    }

    return should_display;
}

Bool @html_text_is_printable_ascii(U8* str)
{
    while (*str) {
        if (*str > 0x7f || *str < ' ')
            return FALSE;
        ++str;
    }
    return TRUE;
}

U8* @doldoc_pt_to_cstring(U8* ptbuf, HtmlRenderer* renderer)
{
    U8* str = CAlloc(MSize2(ptbuf), renderer->task);

    while (*ptbuf) {
        if (!MemCmp(ptbuf, "ER", 2))
            goto pt_to_cstring_done;
        if (!MemCmp(ptbuf, "TX", 2)) {
            ptbuf += 4;
            ptbuf[StrLen(ptbuf) - 1] = NULL;
            StrCpy(str + StrLen(str), ptbuf);
            ptbuf = StrLen(ptbuf) + 2;
            goto pt_to_cstring_next;
        }
        ptbuf = StrLen(ptbuf) + 1;
    pt_to_cstring_next:
    }

pt_to_cstring_done:
    return str;
}

U0 @create_form_from_node(HtmlRenderer* renderer, @html_dom_node* node)
{
    if (!node || !node->attributes || !renderer)
        return;

    JsonObject* form = Json.CreateObject(renderer->task);
    JsonObject* attributes = Json.CreateObject(renderer->task);

    // Copy attributes
    JsonKey* key = node->attributes->keys;
    while (key) {
        attributes->set(key->name, key->value, JSON_STRING);
        key = key->next;
    }

    form->set("attributes", attributes, JSON_OBJECT);
    form->set("elements", Json.CreateArray(renderer->task), JSON_ARRAY);
    renderer->forms->append(form);
    renderer->forms_index = renderer->forms->length - 1;
}

U0 @html_button_clicked(HtmlRenderer* renderer, I64 index, U8* name)
{
    no_warn renderer, index, name;
}

U8* @form_elements_to_string(HtmlRenderer* renderer, JsonObject* form)
{
    if (!form)
        return "";

    JsonObject* attributes = form->@("attributes");
    if (!attributes)
        return "";

    JsonArray* elements = form->@("elements");
    if (!elements)
        return "";

    U8* action = attributes->@("action");
    U8* method = attributes->@("method");

    if (!action)
        action = StrNew(renderer->current_url_string);
    if (!method)
        method = "GET";

    I64 i;
    U8* str = CAlloc(2048, renderer->task);
    JsonObject* element = NULL;

    if (!StrICmp(method, "GET"))
        StrPrint(str, "%s?", attributes->@("action"));

    for (i = 0; i < elements->length; i++) {
        element = elements->@(i);
        StrPrint(str + StrLen(str), "%s=%s", element->@("name"), element->@("value"));
        if (i < elements->length - 1)
            StrCpy(str + StrLen(str), "&");
    }

    return str;
}

U0 @html_submit_form(HtmlRenderer* renderer, I64 index)
{
    if (index < 0 || !renderer || !renderer->forms)
        return;

    JsonObject* form = renderer->forms->@(index);
    if (!form)
        return;

    JsonObject* attributes = form->@("attributes");
    if (!attributes)
        return;

    U8* method = attributes->@("method");

    if (!StrICmp(method, "GET")) {
        @html_follow_link_fp(renderer, @resolve_href(renderer, @form_elements_to_string(renderer, form)));
        return;
    }

    if (!StrICmp(method, "POST")) {
        // FIXME: Implement POST method
        return;
    }
}

U0 @render_form_element(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !renderer || !node->attributes)
        return;

    U8* type = node->attributes->@("type");
    U8* value = node->attributes->@("value");

    if (!type)
        return;

    ButtonWidget* btn = NULL;
    TextInputWidget* input = NULL;
    CheckBoxWidget* cb = NULL;

    if (!StrICmp(type, "checkbox")) {
        cb = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CHECKBOX, U64_MAX, U64_MAX, 14, 14); // FIXME: Derive width/height
        cb->checked = node->attributes->@("checked");
        cb->data = node;
        return;
    }

    if (!StrICmp(type, "button")) {
        btn = Gui.CreateWidget(renderer->win, WIDGET_TYPE_BUTTON, U64_MAX, U64_MAX, 64, 16); // FIXME: Derive width/height
        btn->data = node;
        StrCpy(&btn->text, @t(value, value, ""));
        return;
    }

    if (!StrICmp(type, "submit")) {
        btn = Gui.CreateWidget(renderer->win, WIDGET_TYPE_BUTTON, U64_MAX, U64_MAX, 64, 16); // FIXME: Derive width/height
        btn->data = node;
        // FIXME: Gui.Widget.SetCallback(btn, "clicked", &@form_submit_callback);
        StrCpy(&btn->text, @t(value, value, "Submit"));
        return;
    }

    if (!type || !StrICmp(type, "text")) {
        input = Gui.CreateWidget(renderer->win, WIDGET_TYPE_INPUT, U64_MAX, U64_MAX, 64, 16); // FIXME: Derive width/height
        input->data = node;
        StrCpy(&input->text, @t(value, value, ""));
        return;
    }

    if (!StrICmp(type, "password")) {
        input = Gui.CreateWidget(renderer->win, WIDGET_TYPE_INPUT, U64_MAX, U64_MAX, 64, 16); // FIXME: Derive width/height
        input->is_password = TRUE;
        input->data = node;
        StrCpy(&input->text, @t(value, value, ""));
        return;
    }
}

JsonArray* parent_nodes_excluded_from_text_rendering = Json.Parse("[\"option\",\"script\",\"style\",\"title\"]", erythros_mem_task);
JsonArray* block_level_element_tag_names = Json.Parse("[\"address\",\"article\",\"aside\",\"blockquote\",\"br\",\"canvas\",\"dd\",\"div\",\"dl\",\"dt\",\"fieldset\",\"figcaption\",\"figure\",\"footer\",\"form\",\"h1\",\"h2\",\"h3\",\"h4\",\"h5\",\"h6\",\"header\",\"hr\",\"li\",\"main\",\"nav\",\"noscript\",\"ol\",\"p\",\"pre\",\"section\",\"table\",\"tfoot\",\"ul\",\"video\"]", erythros_mem_task);

U0 @render_node_text(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!@html_text_is_printable_ascii(node->text)) {
        // FIXME: Wire up UTF-8 handling for non-ASCII characters
        return;
    }
    I64 background_color = Color(255, 255, 255); // FIXME: Alpha blend into rect beneath fragment in z-index
    I64 default_font_size = 16;                  // FIXME: Derive this
    U8* font_name = "Free Serif";                // FIXME: Derive this
    I64 font_size = @t(node->parentNode->font_size, node->parentNode->font_size, default_font_size);
    I64 text_width;

    U8* fragments = StrNew(node->text);
    I64 fragment_count = 0;
    U8** fragment = String.Split(fragments, ' ', &fragment_count);
    I64 i;

    Context2DWidget* fragment_widget;

    I64 last_fragment_pos = 0;
    for (i = 0; i < fragment_count; i++) {
        if (fragment[i] && *fragment[i]) {
            last_fragment_pos = i;
            text_width = @get_truetype_text_width(font_name, font_size, fragment[i]);
            if (text_width) {
                text_width += 4;
                fragment_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
                    U64_MAX, U64_MAX, 0, 0);
                fragment_widget->data = node;
                fragment_widget->ctx = NewContext2D(text_width, ToI64(font_size * 1.5))->fill(Color(255, 255, 255))->text(font_name, 0, 0, font_size, node->parentNode->color, fragment[i]);
                fragment_widget->width = fragment_widget->ctx->width;
                fragment_widget->height = fragment_widget->ctx->height;
            }
        }
    }
    Free(fragments);
}

U0 @renderer_append_image(HtmlRenderer* renderer, Context2DWidget* widget)
{
    @window_widgets_list* widget_list_item = CAlloc(sizeof(@window_widgets_list));
    @window_widgets_list* list = renderer->images;
    widget_list_item->widget = widget;
    if (!list) {
        renderer->images = widget_list_item;
    } else {
        while (list->next) {
            list = list->next;
        }
        list->next = widget_list_item;
    }
}

U0 @render_node_list(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !renderer)
        return;

    I64 i;
    U8 buf[HTML_WORK_BUFFER_SIZE];

    I64 margin_top = 32; // FIXME: Derive these
    I64 margin_bottom = 32;

    if (StrICmp(node->tagName, "InternalTextNode") && StrICmp(node->tagName, "option") && StrICmp(node->tagName, "script") && StrICmp(node->tagName, "style") && StrICmp(node->tagName, "title"))
        if (!@render_css_for_node(node, renderer))
            return;

    Context2DWidget* block_widget;

    // FIXME: Resolve if display: block is set
    if (block_level_element_tag_names->contains(node->tagName)) {
        node->display_block = TRUE;
    }

    if (node->display_block) {
        block_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
            U64_MAX, U64_MAX, 0, 0);
        block_widget->data = node;
    }

    if (!StrICmp(node->tagName, "body")) {
        renderer->background_widget->ctx->width = Display.Width();
        renderer->background_widget->ctx->height = Display.Height();
        renderer->background_widget->ctx->fill(@image_pixel_flip_rgb_bgr(node->backgroundColor));
    }

    Context2DWidget* img_widget;

    if (!StrICmp(node->tagName, "form"))
        @create_form_from_node(renderer, node);

    if (!StrICmp(node->tagName, "input"))
        @render_form_element(node, renderer);

    if (!StrICmp(node->tagName, "InternalTextNode")) {
        node->text = @sanitize_node_text(renderer, node->text);
        if (!parent_nodes_excluded_from_text_rendering->contains(node->parentNode->tagName)) {
            @render_node_text(node, renderer);
        }
        if (!StrICmp(node->parentNode->tagName, "title")) {
            String.Trim(node->text);
            Gui.Window.SetTitle(renderer->win, node->text);
            MemSet(renderer->task->task_title, NULL, STR_LEN);
            MemCpy(renderer->task->task_title, node->text, STR_LEN - 1);
            renderer->current_title = StrNew(node->text, renderer->task);
        }
    }

    if (!StrICmp(node->tagName, "img")) {
        if (!node->width || !node->height) {
            node->width = 32;
            node->height = 32;
        }
        img_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
            U64_MAX, U64_MAX, node->width, node->height);
        img_widget->data = node;
        @renderer_append_image(renderer, img_widget);
    }

    if (node->children->length) {
        for (i = 0; i < node->children->length; i++)
            @render_node_list(node->children->@(i), renderer);
    }

    if (node->display_block) {
        block_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
            U64_MAX, U64_MAX, 0, 0);
        block_widget->data = node;
    }
}

@html_dom_node* @self_or_ancestor_matches_tag_name(@html_dom_node* node, U8* tagName)
{
    while (node) {
        if (!StrICmp(node->tagName, tagName))
            return node;
        node = node->parentNode;
    }
    return NULL;
}

U0 @reflow_node_list(HtmlRenderer* renderer)
{
    if (!renderer)
        return;
    if (!renderer->widgets_base)
        return;
    I64 prev_render_y = renderer->render_y;
    renderer->render_x = 0;
    renderer->render_y = renderer->background_widget->y;
    if (renderer->vertical_scroll_widget && prev_render_y && renderer->vertical_scroll_widget->scroll) {
        renderer->render_y -= (renderer->vertical_scroll_widget->scroll * (prev_render_y / renderer->vertical_scroll_widget->height));
    }
    renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;

    @window_widgets_list* widget_list_item = renderer->widgets_base->next;
    Widget* widget;
    @html_dom_node* node;

    while (widget_list_item) {
        widget = widget_list_item->widget;
        node = widget->data;

        if (node) {
            if (node->display_block && renderer->render_x) {
                renderer->render_x = 0;
                renderer->render_y += renderer->max_line_height;
                renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
            }

            widget->x = renderer->render_x;
            widget->y = renderer->render_y;
            if (@self_or_ancestor_matches_tag_name(node, "a")) {
                widget->pointer = renderer->link_pointer;
                Gui.Widget.SetCallback(widget, "clicked", renderer->link_callback);
            }

            renderer->render_x += widget->width;
            renderer->max_line_height = Max(renderer->max_line_height, widget->height);

            if (renderer->render_x > renderer->win->width - widget->width) {
                renderer->render_x = 0;
                renderer->render_y += renderer->max_line_height;
                renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
            }
        }

        widget_list_item = widget_list_item->next;
    }
}

U0 @process_css_rules_from_external_stylesheet(HtmlRenderer* renderer, U8* str)
{
    // download (or load from cache) and process stylesheet
    if (!renderer || !str)
        return;
    U8 status_text_buffer[128];
    U8 buf[HTML_WORK_BUFFER_SIZE];
    HttpUrl* url = @expand_url_from_string(renderer->task, renderer->current_url, str);
    if (!url)
        return;
    StrPrint(buf, "%s%s%s", url->scheme, url->host, url->path);
    U8* buffer = NULL;
    @http_response* resp = NULL;
    I64 content_length = 0;
    if (@http_is_resource_cached(buf, renderer->cache_directory)) {
        StrPrint(status_text_buffer, "Loading CSS file from cache: %s", buf);
        @html_renderer_update_status_text(renderer, status_text_buffer);
        resp = CAlloc(sizeof(@http_response), renderer->task);
        resp->body.data = FileRead(@http_get_cached_resource_filename(buf, renderer->cache_directory), &content_length);
    } else {
        StrPrint(status_text_buffer, "Fetching %s...", buf);
        @html_renderer_update_status_text(renderer, status_text_buffer);
        buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, renderer->task);
        resp = Http.Get(url, buffer);
        while (resp->state != HTTP_STATE_DONE) {
            if (resp->state >= HTTP_STATE_HEADERS_RECEIVED) {
                StrPrint(status_text_buffer, "Received %d bytes", resp->body.length);
                @html_renderer_update_status_text(renderer, status_text_buffer);
            }
            Sleep(1);
        }
        content_length = StrLen(resp->body.data);
        if (!content_length)
            goto @css_content_length_is_zero;
        @http_cache_resource(buf, resp->body.data, content_length, renderer->cache_directory);
    }

    @css_tokenize_and_create_rules_from_buffer(renderer->css_rules, resp->body.data, content_length, renderer->task);

    @css_content_length_is_zero : if (buffer) Free(buffer);
}

U0 @process_css_rules_from_node_list(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node)
        return;
    I64 i;
    U8 node_ptr_string[32];
    U8 tmpbuf[HTML_WORK_BUFFER_SIZE];
    U8* tmpmd5;

    // Process rules from LINK rel="stylesheet" elements
    if (!StrICmp(node->tagName, "link")) {
        if (!StrICmp(node->attributes->@("rel"), "stylesheet") && StrLen(node->attributes->@("rel")) == 10 && node->attributes->@("href")) {
            @process_css_rules_from_external_stylesheet(renderer, node->attributes->@("href"));
        }
    }

    // Process rules from STYLE elements
    if (!StrICmp(node->tagName, "InternalTextNode"))
        if (!StrICmp(node->parentNode->tagName, "style"))
            @css_tokenize_and_create_rules_from_buffer(renderer->css_rules, node->text, StrLen(node->text), renderer->task);

    // Process rules from style attributes on individual elements
    if (StrICmp(node->tagName, "link") && node->attributes->@("style")) {
        StrPrint(node_ptr_string, "0x%08x", node);
        tmpmd5 = md5_string(node_ptr_string, StrLen(node_ptr_string));
        StrPrint(tmpbuf, "\xFE%s{%s}", tmpmd5, node->attributes->@("style"));
        @css_tokenize_and_create_rules_from_buffer(renderer->css_rules, tmpbuf, StrLen(tmpbuf), renderer->task);
        Free(tmpmd5);
    }

    if (node->children->length) {
        for (i = 0; i < node->children->length; i++)
            @process_css_rules_from_node_list(node->children->@(i), renderer);
    }
}

U0 @process_custom_css_rules(HtmlRenderer* renderer)
{
    JsonItem* item;
    JsonArray* rules = NULL;
    I64 i;
    rules = @custom_css_rules->@(renderer->current_url->host);
    if (rules) {
        for (i = 0; i < rules->length; i++) {
            renderer->css_rules->append(rules->@(i));
        }
        return;
    }
}

U0 @fetch_images_for_page(HtmlRenderer* renderer)
{
    if (!renderer) {
        return;
    }

    U8 status_text_buffer[128];
    U8 buf[HTML_WORK_BUFFER_SIZE];
    HttpUrl* url;
    Context2DWidget* widget;
    @html_dom_node* node;
    U8* src;
    Bool is_alternate_port;
    U8* buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, renderer->task);
    @http_response* resp = NULL;

    @window_widgets_list* image_list_item = renderer->images;
    while (image_list_item) {

        widget = image_list_item->widget;
        if (!widget)
            goto @fetch_next_image;
        node = widget->data;
        if (!node)
            goto @fetch_next_image;
        src = node->attributes->@("src");
        if (!src)
            goto @fetch_next_image;
        url = @expand_url_from_string(renderer->task, renderer->current_url, src);
        if (!url)
            goto @fetch_next_image;

        is_alternate_port = FALSE;
        if (!StrICmp(url->scheme, "http://") && url->port != 80)
            is_alternate_port = TRUE;
        if (!StrICmp(url->scheme, "https://") && url->port != 443)
            is_alternate_port = TRUE;
        if (is_alternate_port)
            StrPrint(buf, "%s%s:%d%s", url->scheme, url->host, url->port, url->path);
        else
            StrPrint(buf, "%s%s%s", url->scheme, url->host, url->path);

        if (@http_is_resource_cached(buf, renderer->cache_directory)) {
            StrPrint(status_text_buffer, "Loading image from cache: %s", buf);
            @html_renderer_update_status_text(renderer, status_text_buffer);
            resp = CAlloc(sizeof(@http_response), renderer->task);
            resp->body.data = FileRead(@http_get_cached_resource_filename(buf, renderer->cache_directory), &resp->body.length);
        } else {
            StrPrint(status_text_buffer, "Fetching %s...", buf);
            @html_renderer_update_status_text(renderer, status_text_buffer);
            buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, renderer->task);
            resp = Http.Get(url, buffer);
            while (resp->state != HTTP_STATE_DONE) {
                if (resp->state >= HTTP_STATE_HEADERS_RECEIVED) {
                    StrPrint(status_text_buffer, "Received %d bytes", resp->body.length);
                    @html_renderer_update_status_text(renderer, status_text_buffer);
                }
                Sleep(1);
            }
            if (!resp->body.length)
                goto @fetch_next_image;
            @http_cache_resource(buf, resp->body.data, resp->body.length, renderer->cache_directory);
        }

        // FIXME: Wire up animated GIF handling
        widget->ctx = @image_buffer_to_context2d(resp->body.data, resp->body.length);
        if (widget->ctx) {
            widget->width = widget->ctx->width;
            widget->height = widget->ctx->height;
        }

        @reflow_node_list(renderer);
        @fetch_next_image : image_list_item = image_list_item->next;
    }

    Free(buffer);
}