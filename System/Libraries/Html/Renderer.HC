// Structure for the ICO header
class @ico_header
{
    U16 reserved; // Reserved, must be 0
    U16 type;     // Type: 1 for icon, 2 for cursor
    U16 count;    // Number of images in the file
};

// Structure for the image directory entry
class @ico_entry
{
    U8 width;           // Width of the image
    U8 height;          // Height of the image
    U8 color_count;     // Number of colors (0 if >= 256)
    U8 reserved;        // Reserved, must be 0
    U16 planes;         // Color planes
    U16 bits_per_pixel; // Bits per pixel
    U32 size_in_bytes;  // Size of the image data
    U32 data_offset;    // Offset to the image data
};

class BITMAPFILEHEADER {
    U16 bfType;
    U32 bfSize;
    U16 bfReserved1;
    U16 bfReserved2;
    U32 bfOffBits;
    U32 bV5Size;
    I32 bV5Width;
    I32 bV5Height;
    U16 bV5Planes;
    U16 bV5BitCount;
    U32 bV5Compression;
    U32 bV5SizeImage;
    U8 pad[100];
};

#define RENDERER_DEFAULT_MAX_LINE_HEIGHT 17

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
    Bool debug;
    Bool last_char_was_whitespace;
    Bool enable_animations;
    Bool enable_lazy_loading;
    U8 status_text[128];
    VerticalScrollBarWidget* vertical_scroll_widget;
    TextLabelWidget* status_widget;
    Context2DWidget* background_widget;
    Context2D* background_ctx;
    Window* win;
    @window_widgets_list* widgets_base;
    @window_widgets_list* images;
    I64 render_x;
    I64 render_y;
    I64 indent;
    I64 max_line_height;
    I64 calculated_page_height;
    Context2D* link_pointer;
    U64 link_callback;
};

#define HtmlRenderer @html_renderer

#define HTML_WORK_BUFFER_SIZE 2048

// Initialize CSS default rules
JsonArray* CSS_DEFAULT_RULES = Json.CreateArray(erythros_mem_task);

I64 css_default_rules_buffer_length = 0;
U8* css_default_rules_buffer = FileRead("M:/Applications/Internet/Cyberia.app/Resources/Default.css", &css_default_rules_buffer_length);
@css_tokenize_and_create_rules_from_buffer(CSS_DEFAULT_RULES, css_default_rules_buffer, css_default_rules_buffer_length, erythros_mem_task);

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

Bool @apply_css_rules_to_node(@html_dom_node* node, HtmlRenderer* renderer)
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
    U8* match_font_family;
    JsonKey* font_key;

    if (!node)
        return FALSE;
    if (node->parentNode) {
        node->backgroundColor = node->parentNode->backgroundColor;
        node->color = node->parentNode->color;
        node->fontFamily = node->parentNode->fontFamily;
        node->fontSize = node->parentNode->fontSize;
        node->fontWeight = node->parentNode->fontWeight;
        node->textAlign = node->parentNode->textAlign;
    }

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

            // try to match tagName
            if (!StrICmp(matches->@(0), node->tagName)) {
                matched = TRUE;
                goto @css_rule_check_if_matched;
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
                        node->fontSize = ToI64((Str2I64(node_tmpnum_buf) / 3) * 2);
                    }

                    if (!StrICmp(key->name, "font-size")) {
                        StrCpy(node_tmpnum_buf, values->@(0));
                        if (!StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "em")) {
                            node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                            node->fontSize = ToI64(Str2F64(node_tmpnum_buf) * RENDERER_DEFAULT_MAX_LINE_HEIGHT);
                        }
                        if (!StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "px")) {
                            node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                            node->fontSize = Str2I64(node_tmpnum_buf);
                        }
                    }

                    if (!StrICmp(key->name, "font-weight")) {
                        if (values->@(0)(U8*)[0] >= '0' && values->@(0)(U8*)[0] <= '9') {
                            node->fontWeight = Str2I64(values->@(0));
                        }
                        if (!StrICmp(values->@(0), "bold")) {
                            node->fontWeight = 700;
                        }
                        if (!StrICmp(values->@(0), "normal")) {
                            node->fontWeight = 400;
                        }
                    }

                    if (!StrICmp(key->name, "font-family")) {
                        for (k = 0; k < values->length; k++) {

                            match_font_family = values->@(k);
                            String.Trim(match_font_family);
                            String.Trim(match_font_family, '"');

                            font_key = Fonts->keys;
                            while (font_key) {
                                if (!StrICmp(font_key->name, match_font_family)) {
                                    node->fontFamily = font_key->name;
                                    goto css_continue_to_next_property;
                                }
                                font_key = font_key->next;
                            }
                        }
                    }
                css_continue_to_next_property:
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
JsonArray* block_level_element_tag_names = Json.Parse("[\"address\",\"article\",\"aside\",\"blockquote\",\"canvas\",\"dd\",\"div\",\"dl\",\"dt\",\"fieldset\",\"figcaption\",\"figure\",\"footer\",\"form\",\"h1\",\"h2\",\"h3\",\"h4\",\"h5\",\"h6\",\"header\",\"hr\",\"li\",\"main\",\"nav\",\"noscript\",\"ol\",\"p\",\"pre\",\"section\",\"table\",\"tfoot\",\"ul\",\"video\"]", erythros_mem_task);

#define ADD_BYTE_TO_CODE_POINT_VALUE code_point = ((code_point << 6) | text[++i] & 0x3f);
#define ADD_TWO_BYTES_TO_CODE_POINT_VALUE ADD_BYTE_TO_CODE_POINT_VALUE ADD_BYTE_TO_CODE_POINT_VALUE
#define ADD_THREE_BYTES_TO_CODE_POINT_VALUE ADD_TWO_BYTES_TO_CODE_POINT_VALUE ADD_BYTE_TO_CODE_POINT_VALUE

I32* @I32_text_stream_from_utf8(U8* text, I64* count)
{
    if (!text || !StrLen(text))
        return NULL;
    I64 i = 0;
    I64 j = 0;
    I32 ch;
    I32 code_point;
    I32* stream = CAlloc((StrLen(text) + 1) * sizeof(I32), erythros_mem_task);
    while (ch = text[i]) {
        if (ch < 0x80) {
            stream[j++] = ch;
            goto @parse_next_utf8_byte;
        }
        if (ch & 0xf0 == 0xf0) {
            code_point = ch & 0x7;
            ADD_THREE_BYTES_TO_CODE_POINT_VALUE
        } else if (ch & 0xe0 == 0xe0) {
            code_point = ch & 0xf;
            ADD_TWO_BYTES_TO_CODE_POINT_VALUE
        } else if (ch & 0xc0 == 0xc0) {
            code_point = ch & 0x1f;
            ADD_BYTE_TO_CODE_POINT_VALUE
        } else {
            code_point = '?'; // Invalid character
            goto @parse_next_utf8_byte;
        }
        stream[j++] = code_point;
        @parse_next_utf8_byte : ++i;
    }
    *count = j;
    return stream;
}

Bool @code_point_is_whitespace(I32 code_point)
{
    switch (code_point) {
    case 0x09...0x0d:
    case 0x20:
    case 0x85:
    case 0xa0:
    case 0x1680:
    case 0x2000...0x200a:
    case 0x2028:
    case 0x2029:
    case 0x202f:
    case 0x205f:
    case 0x3000:
        return TRUE;
    default:
        return FALSE;
    }
}

U8* @resolved_font_weight_for_node(@html_dom_node* node)
{
    U8 buf[128];
    if (!node || !node->fontFamily || !StrLen(node->fontFamily))
        return;
    switch (node->fontWeight) {
    case 700:
    case 800:
    case 900:
        if (!StrICmp(node->fontFamily + StrLen(node->fontFamily) - 4, "bold")) {
            return node->fontFamily;
        } else {
            StrPrint(buf, "%s Bold", node->fontFamily);
            if (Fonts->@(buf)) {
                return StrNew(buf, erythros_mem_task);
            } else {
                // Can't find Bold variant, return Normal
                return node->fontFamily;
            }
        }
        break;
    default:
        return node->fontFamily;
        break;
    }
}

U0 @render_node_text(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !renderer || !node->text || !StrLen(node->text))
        return;

    I64 i, j;
    node->textAlign = node->parentNode->textAlign;

    // Convert all the code points to I32
    I64 code_point_count = 0;
    I64 code_point_offset = 0;
    I32* stream = @I32_text_stream_from_utf8(node->text, &code_point_count);

    // L-R Trim all the whitespace code points
    while (stream[code_point_offset] && @code_point_is_whitespace(stream[code_point_offset]))
        ++code_point_offset;
    while (@code_point_is_whitespace(stream[code_point_offset + code_point_count - 1]))
        --code_point_count;

    // Get the fragment count
    I64 fragment_count = 0;
    for (i = code_point_offset; i < code_point_count; i++) {
        if (@code_point_is_whitespace(stream[i]))
            ++fragment_count;
    }
    ++fragment_count;

    // Calculate fragment pointers and NULL terminate fragments
    I32** fragments = CAlloc(sizeof(I32*) * (fragment_count));
    I64 fragment_base = code_point_offset;
    j = 0;
    for (i = code_point_offset; i < code_point_count; i++) {
        if (@code_point_is_whitespace(stream[i])) {
            fragments[j] = &stream[fragment_base];
            stream[i] = NULL;
            fragment_base = i + 1;
            ++j;
        }
    }
    fragments[j] = &stream[fragment_base];
    stream[i] = NULL;
    fragment_base = i + 1;

    I64 text_width;
    Context2DWidget* fragment_widget;

    U32 fragment_bounding_box_color = Color(0x00, 0xff, 0x00);
    U8* font_name = @resolved_font_weight_for_node(node->parentNode);
    "font_name: %s\n", font_name;

    for (i = 0; i < fragment_count; i++) {
        if (fragments[i] && *fragments[i]) {
            text_width = @get_truetype_text_width(font_name, node->parentNode->fontSize, fragments[i]);
            if (text_width) {
                text_width += 4;
                fragment_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
                    U64_MAX, U64_MAX, 0, 0);
                fragment_widget->data = node;
                fragment_widget->ctx = NewContext2D(text_width, ToI64(node->parentNode->fontSize * 1.2))->fill(node->parentNode->backgroundColor)->text(font_name, 0, 0, node->parentNode->fontSize, node->parentNode->color, fragments[i]);

                if (renderer->debug && fragment_widget->ctx) {
                    fragment_widget->ctx->line(0, 0, fragment_widget->ctx->width - 1, 0, fragment_bounding_box_color);
                    fragment_widget->ctx->line(0, fragment_widget->ctx->height - 1, fragment_widget->ctx->width - 1, fragment_widget->ctx->height - 1, fragment_bounding_box_color);
                    fragment_widget->ctx->line(0, 0, 0, fragment_widget->ctx->height - 1, fragment_bounding_box_color);
                    fragment_widget->ctx->line(fragment_widget->ctx->width - 1, 0, fragment_widget->ctx->width - 1, fragment_widget->ctx->height - 1, fragment_bounding_box_color);
                }

                fragment_widget->width = fragment_widget->ctx->width;
                fragment_widget->height = fragment_widget->ctx->height;
            }
        }
    }
    Free(fragments);
    Free(stream);
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

U0 @apply_attribute_values_to_node(@html_dom_node* node)
{
    if (!node)
        return;

    if (node->attributes->@("bgcolor")) {
        if (@css_named_colors->@(node->attributes->@("bgcolor"))) {
            node->backgroundColor = @css_resolve_color_from_rrggbb(@css_named_colors->@(node->attributes->@("bgcolor")));
        } else if (node->attributes->@("bgcolor")(U8*)[0] == '#') {
            node->backgroundColor = @css_resolve_color_from_rrggbb(node->attributes->@("bgcolor"));
        }
    }

    if (node->attributes->@("color")) {
        if (@css_named_colors->@(node->attributes->@("color"))) {
            node->color = @css_resolve_color_from_rrggbb(@css_named_colors->@(node->attributes->@("color")));
        } else if (node->attributes->@("color")(U8*)[0] == '#') {
            node->color = @css_resolve_color_from_rrggbb(node->attributes->@("color"));
        }
    }

    if (node->attributes->@("align")) {
        if (!StrICmp(node->attributes->@("align"), "center"))
            node->textAlign = CSS_TEXT_ALIGN_CENTER;
        if (!StrICmp(node->attributes->@("align"), "right"))
            node->textAlign = CSS_TEXT_ALIGN_RIGHT;
    }

    if (!StrICmp(node->tagName, "center"))
        node->textAlign = CSS_TEXT_ALIGN_CENTER;
}

U0 @render_node_list(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !renderer)
        return;

    I64 i;
    U8 buf[HTML_WORK_BUFFER_SIZE];

    Context2DWidget* block_widget;
    Context2DWidget* img_widget;

    // FIXME: Resolve if display: block is set
    if (block_level_element_tag_names->contains(node->tagName)) {
        node->display_block = TRUE;
    }

    if (StrICmp(node->tagName, "InternalTextNode"))
        if (!@apply_css_rules_to_node(node, renderer))
            return;

    ++renderer->indent;

    @apply_attribute_values_to_node(node);

    if (renderer->debug && StrICmp(node->tagName, "InternalTextNode")) {
        for (i = 0; i < renderer->indent; i++)
            "  ";
        "<%s> textAlign: %d, width: %d, height: %d, bg: #0x%06x, color: #0x%06x, fontFamily: '%s', fontSize: %d, fontWeight: %d, display_block: %d\n",
            node->tagName, node->textAlign, node->width, node->height, node->backgroundColor, node->color, node->fontFamily, node->fontSize, node->fontWeight, node->display_block;
    }

    // Insert a block widget for the element's opening tag
    if (node->display_block) {
        block_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
            U64_MAX, U64_MAX, 0, 0);
        block_widget->data = node;
    }

    if (!StrICmp(node->tagName, "b")) {
        node->fontWeight = 700;
    }

    if (!StrICmp(node->tagName, "body")) {
        renderer->background_ctx->width = Display.Width();
        renderer->background_ctx->height = Display.Height();
        renderer->background_ctx->fill(@image_pixel_flip_rgb_bgr(node->backgroundColor));
    }

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

    // Insert a block widget for the element's closing tag
    if (node->display_block || !StrICmp(node->tagName, "br")) {
        block_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
            U64_MAX, U64_MAX, 0, 0);
        block_widget->data = node;
    }

    --renderer->indent;
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

    renderer->render_x = 0;
    renderer->render_y = 0;
    renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;

    VerticalScrollBarWidget* vscroll = renderer->vertical_scroll_widget;

    renderer->background_widget->ctx = renderer->background_ctx;
    I64 origin_y = renderer->background_widget->y;
    I64 offset_y = origin_y;
    I64 line_break_max = 0;
    I64 minimum_vscroll_value = 0;
    if (vscroll && vscroll->max && vscroll->value) {
        minimum_vscroll_value = ToI64((vscroll->max * 1.0) / (vscroll->height * 1.0) * (16 * 1.0));
        offset_y -= vscroll->value - minimum_vscroll_value;
    }

    @html_dom_node* node;
    @html_dom_node* cumulative_node;
    I64 cumulative_widgets_width;
    @window_widgets_list* widget_list_item = renderer->widgets_base->next;
    @window_widgets_list* cumulative_list_item;
    Widget* widget;

    while (widget_list_item) {
        widget = widget_list_item->widget;
        node = widget->data;

        if (node) {

            if (!StrICmp(node->tagName, "br")) {
                renderer->render_x = 0;
                renderer->render_y += renderer->max_line_height;
                renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
                goto reflow_next_list_item;
            }

            if (node->display_block) {
                if (renderer->render_x) {
                    renderer->render_x = 0;
                    renderer->render_y += renderer->max_line_height;
                    renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
                }
                goto reflow_next_list_item;
            }

            if (!renderer->render_x && node->textAlign) {
                // Begin calculating x offset for text alignment
                cumulative_widgets_width = widget->width;
                cumulative_list_item = widget_list_item->next;
                while (cumulative_list_item && cumulative_list_item->widget && cumulative_list_item->widget->data) {
                    cumulative_node = cumulative_list_item->widget->data;
                    if (cumulative_node->display_block || !StrICmp(cumulative_node->tagName, "br")) {
                        cumulative_list_item = NULL;
                    } else {
                        cumulative_widgets_width += cumulative_list_item->widget->width;
                        cumulative_list_item = cumulative_list_item->next;
                    }
                }
                switch (node->textAlign) {
                case CSS_TEXT_ALIGN_CENTER:
                    renderer->render_x = (renderer->win->width / 2) - (cumulative_widgets_width / 2);
                    break;
                case CSS_TEXT_ALIGN_RIGHT:
                    renderer->render_x = -8 + renderer->win->width - cumulative_widgets_width;
                    break;
                default:
                    "ERROR: Invalid node->textAlign value: %d\n", node->textAlign;
                    PressAKey;
                    break;
                }
            }

            line_break_max = 8;
            if (!node->textAlign) {
                line_break_max += widget->width + 16;
            }

            widget->x = renderer->render_x;
            widget->y = renderer->render_y + offset_y;

            if (@self_or_ancestor_matches_tag_name(node, "a")) {
                widget->pointer = renderer->link_pointer;
                Gui.Widget.SetCallback(widget, "clicked", renderer->link_callback);
            }

            renderer->render_x += widget->width;
            renderer->max_line_height = Max(renderer->max_line_height, widget->height);

            if (renderer->render_x > renderer->win->width - line_break_max) {
                renderer->render_x = 0;
                renderer->render_y += renderer->max_line_height;
                renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
            }
        }
    reflow_next_list_item:

        widget_list_item = widget_list_item->next;
    }

    if (renderer->render_x) {
        renderer->render_x = 0;
        renderer->render_y += renderer->max_line_height;
        renderer->max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
    }

    renderer->calculated_page_height = renderer->render_y - origin_y;
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

Context2D* DEFAULT_FAVICON = @image_file_to_context2d("M:/Applications/Internet/Icon.png");

Context2D* @process_favicon(Context2D* tmpctx)
{
    Context2D* favicon_ctx = DEFAULT_FAVICON;
    if (tmpctx) {
        if (tmpctx->width == 16 && tmpctx->height == 16) {
            favicon_ctx = tmpctx;
        } else {
            favicon_ctx = Scale2D(tmpctx, ToF64(16.0 / (tmpctx->width * 1.0)), ToF64(16.0 / (tmpctx->height * 1.0)));
            DelContext2D(tmpctx);
        }
    }
    return favicon_ctx;
}

Context2D* @favicon_for_page(HtmlRenderer* renderer)
{
    if (!renderer)
        return DEFAULT_FAVICON;

    U8 status_text_buffer[128];
    U8 buf[HTML_WORK_BUFFER_SIZE];
    HttpUrl* url;
    Context2DWidget* widget;
    @html_dom_node* node;
    U8* src;
    Bool is_alternate_port;
    @http_response* resp = NULL;

    url = @expand_url_from_string(renderer->task, renderer->current_url, "/favicon.ico");
    if (!url)
        return DEFAULT_FAVICON;

    U8* buffer = CAlloc(HTTP_FETCH_BUFFER_SIZE, renderer->task);

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
        StrPrint(status_text_buffer, "Loading favicon from cache: %s", buf);
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
        if (!resp->body.length) {
            Free(buffer);
            return DEFAULT_FAVICON;
        }
        @http_cache_resource(buf, resp->body.data, resp->body.length, renderer->cache_directory);
    }

    Context2D* favicon_ctx = DEFAULT_FAVICON;

    if (MemCmp(resp->body.data, "\x00\x00\x01\x00", 4)) {
        // Try processing the data as some other supported image format
        favicon_ctx = @process_favicon(@image_buffer_to_context2d(resp->body.data, resp->body.length));
        Free(buffer);
        return favicon_ctx;
    }

    U8* favicon_buffer = NULL;
    I64 favicon_length = 0;

    @ico_header* ico_header = resp->body.data;
    @ico_entry* ico_entry = (ico_header(U64) + sizeof(@ico_header));

    I64 i = 0;
    while (i < ico_header->count) {
        if ((ico_entry->width == 16 && ico_entry->height == 16) || ico_header->count == 1) {
            favicon_buffer = resp->body.data + ico_entry->data_offset;
            favicon_length = ico_entry->size_in_bytes;
            break;
        }
        ++ico_entry;
        ++i;
    }

    if (favicon_buffer && favicon_length) {

        if (!MemCmp(favicon_buffer, "\x89PNG", 4)) {
            // Image data is png, no need to get fancy
            favicon_ctx = @process_favicon(@image_buffer_to_context2d(favicon_buffer, favicon_length));
            Free(buffer);
            return favicon_ctx;
        }

        // Let's slap a bmp header on this bad boy
        I64 bmp_length = favicon_length + sizeof(BITMAPFILEHEADER);
        BITMAPFILEHEADER* bmp = CAlloc(bmp_length, renderer->task);
        MemCpy(bmp(U64) + sizeof(BITMAPFILEHEADER), favicon_buffer, favicon_length);

        bmp->bfType = 'BM';
        bmp->bfOffBits = *(favicon_buffer(U32*));
        bmp->bfOffBits += sizeof(BITMAPFILEHEADER) - 20;
        bmp->bV5Size = 0x7c; // BITMAPV5
        bmp->bV5Width = ico_entry->width;
        bmp->bV5Height = ico_entry->height;
        bmp->bV5Planes = ico_entry->planes;
        bmp->bV5BitCount = ico_entry->bits_per_pixel;

        favicon_ctx = @process_favicon(@image_buffer_to_context2d(bmp, bmp_length));
        Free(bmp);
    }

    Free(buffer);
    return favicon_ctx;
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