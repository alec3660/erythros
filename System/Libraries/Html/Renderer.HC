JsonArray* border_style_values = Json.Parse("[\"none\",\"hidden\",\"dotted\",\"dashed\",\"solid\",\"double\",\"groove\",\"ridge\",\"inset\",\"outset\"]", erythros_mem_task);
JsonArray* block_level_element_tag_names = Json.Parse("[\"address\",\"article\",\"aside\",\"blockquote\",\"canvas\",\"dd\",\"div\",\"dl\",\"dt\",\"fieldset\",\"figcaption\",\"figure\",\"footer\",\"form\",\"h1\",\"h2\",\"h3\",\"h4\",\"h5\",\"h6\",\"header\",\"hr\",\"li\",\"main\",\"nav\",\"noscript\",\"ol\",\"p\",\"pre\",\"section\",\"table\",\"tfoot\",\"ul\",\"video\"]", erythros_mem_task);
JsonArray* parent_nodes_excluded_from_text_rendering = Json.Parse("[\"option\",\"script\",\"style\",\"title\"]", erythros_mem_task);
JsonArray* text_align_values = Json.Parse("[\"left\",\"center\",\"right\"]", erythros_mem_task);
JsonArray* display_values = Json.Parse("[\"none\",\"block\",\"inline\",\"inline-block\"]", erythros_mem_task);

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

class @renderer_reflow_bounds
{
    I32 x1;
    I32 x2;
    I32 y1;
    I32 y2;
}

class @renderer_reflow_inline
{
    I32 x;
    I32 y;
    I64 max_line_height;
}

class @renderer_reflow
{
    @renderer_reflow_bounds bounds;
    @renderer_reflow_inline inline;
    Widget* parent;
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
    RectWidget* background_widget;
    U32 background_color;
    Window* win;
    @window_widgets_list* widgets_base;
    @window_widgets_list* images;
    I64 inline_x;
    I64 inline_y;
    I64 render_x;
    I64 render_y;
    I64 scroll_y;
    I64 indent;
    I64 calculated_page_height;
    Context2D* link_pointer;
    U64 link_callback;
    U64 form_submit_callback;
    U64 (*image_load_callback)(U64);
    @renderer_reflow reflow_stack[128];
    @renderer_reflow reflow;
    I64 reflow_index;
};

#define HtmlRenderer @html_renderer

#define HTML_WORK_BUFFER_SIZE 4096

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

U0 (*@html_follow_link_fp)(HtmlRenderer* renderer, U8* url_string) = NULL;

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

U32 @css_resolve_color_from_rgba_tuple(U8* str)
{
    U8 buffer[128];

    I64 i;
    I64 comp[4];
    I64 cnt;
    while (*str < '0' || *str > '9') {
        ++str;
    }
    StrCpy(buffer, str);
    String.Trim(buffer, ')');
    U8** channel = String.Split(buffer, ',', &cnt);

    for (i = 0; i < 4; i++) {
        if (StrOcc(channel[i], '%')) {
            String.Trim(channel[i], '%');
            comp[i] = ToI64(2.55 * Str2F64(channel[i]));
        } else if (StrOcc(channel[i], '.')) {
            // FIXME: Do alpha blending when we eventually support transparency
            comp[i] = 255;
        } else {
            comp[i] = Str2I64(i);
        }
    }
    Free(channel);
    return Color(comp[0], comp[1], comp[2], comp[3]);
}

U32 @css_resolve_color_from_rgb_tuple(U8* str)
{
    U8 buffer[128];

    I64 i;
    I64 comp[3];
    I64 cnt;
    while (*str < '0' || *str > '9') {
        ++str;
    }
    StrCpy(buffer, str);
    String.Trim(buffer, ')');
    U8** channel = String.Split(buffer, ',', &cnt);

    for (i = 0; i < 3; i++) {
        if (StrOcc(channel[i], '%')) {
            String.Trim(channel[i], '%');
            comp[i] = ToI64(2.55 * Str2F64(channel[i]));
        } else {
            comp[i] = Str2I64(i);
        }
    }
    Free(channel);
    return Color(comp[0], comp[1], comp[2]);
}

U0 @css_resolve_color(U8* str, U32* dst)
{
    if (@css_named_colors->@(str)) {
        *dst = @css_resolve_color_from_rrggbb(@css_named_colors->@(str));
    } else if (*str == '#') {
        *dst = @css_resolve_color_from_rrggbb(str);
    } else if (!MemCmp(str, "rgba", 4)) {
        *dst = @css_resolve_color_from_rgba_tuple(str);
    } else if (!MemCmp(str, "rgb", 3)) {
        *dst = @css_resolve_color_from_rgb_tuple(str);
    } else {
        // unsupported; do nothing
    }
}

U0 @set_css_distance(U8* str, F64* value, I64* type)
{
    if (!str || !value || !type)
        return;
    if (!StrICmp(str, "0")) {
        *value = 0;
        *type = CSS_DISTANCE_UNDEFINED;
        return;
    }
    if (!StrICmp(str, "auto")) {
        *type = CSS_DISTANCE_AUTO;
        return;
    }
    U8 buf[16];
    StrCpy(buf, str);
    if (String.EndsWith("px", buf)) {
        buf[StrLen(buf) - 2] = NULL;
        *value = Str2F64(buf);
        *type = CSS_DISTANCE_PIXELS;
        return;
    }
    if (String.EndsWith("em", buf)) {
        buf[StrLen(buf) - 2] = NULL;
        *value = Str2F64(buf);
        *type = CSS_DISTANCE_EM;
        return;
    }
    if (String.EndsWith("%", buf)) {
        buf[StrLen(buf) - 1] = NULL;
        *value = Str2F64(buf);
        *type = CSS_DISTANCE_PERCENT;
        return;
    }
}

U0 @set_css_border_style(U8* str, I64* style)
{
    I64 i;
    U8* value = NULL;
    for (i = 0; i < border_style_values->length; i++) {
        value = border_style_values->@(i);
        if (!StrICmp(str, value)) {
            *style = i;
            return;
        }
    }
}

U0 @set_css_border_width(U8* str, F64* value, I64* type)
{
    if (StrFind("%", str))
        return;
    if (!StrICmp(str, "thin")) {
        *value = 1;
        *type = CSS_DISTANCE_PIXELS;
        return;
    }
    if (!StrICmp(str, "medium")) {
        *value = 3;
        *type = CSS_DISTANCE_PIXELS;
        return;
    }
    if (!StrICmp(str, "thick")) {
        *value = 5;
        *type = CSS_DISTANCE_PIXELS;
        return;
    }
    @set_css_distance(str, value, type);
}

U0 @css_resolve_border_color(@html_dom_node* node, JsonArray* values)
{
    if (!node || !values || !values->length)
        return;
    switch (values->length) {
    case 2:
        @css_resolve_color(values->@(0), &node->border.topColor);
        @css_resolve_color(values->@(0), &node->border.bottomColor);
        @css_resolve_color(values->@(1), &node->border.leftColor);
        @css_resolve_color(values->@(1), &node->border.rightColor);
        break;
    case 3:
        @css_resolve_color(values->@(0), &node->border.topColor);
        @css_resolve_color(values->@(1), &node->border.leftColor);
        @css_resolve_color(values->@(1), &node->border.rightColor);
        @css_resolve_color(values->@(2), &node->border.bottomColor);
        break;
    case 4:
        @css_resolve_color(values->@(0), &node->border.topColor);
        @css_resolve_color(values->@(1), &node->border.rightColor);
        @css_resolve_color(values->@(2), &node->border.bottomColor);
        @css_resolve_color(values->@(3), &node->border.leftColor);
        break;
    default:
        @css_resolve_color(values->@(0), &node->border.topColor);
        @css_resolve_color(values->@(0), &node->border.rightColor);
        @css_resolve_color(values->@(0), &node->border.bottomColor);
        @css_resolve_color(values->@(0), &node->border.leftColor);
        break;
    }
}

U0 @css_resolve_border_style(@html_dom_node* node, JsonArray* values)
{
    if (!node || !values || !values->length)
        return;
    switch (values->length) {
    case 2:
        @set_css_border_style(values->@(0), &node->border.topStyle);
        @set_css_border_style(values->@(0), &node->border.bottomStyle);
        @set_css_border_style(values->@(1), &node->border.leftStyle);
        @set_css_border_style(values->@(1), &node->border.rightStyle);
        break;
    case 3:
        @set_css_border_style(values->@(0), &node->border.topStyle);
        @set_css_border_style(values->@(1), &node->border.leftStyle);
        @set_css_border_style(values->@(1), &node->border.rightStyle);
        @set_css_border_style(values->@(2), &node->border.bottomStyle);
        break;
    case 4:
        @set_css_border_style(values->@(0), &node->border.topStyle);
        @set_css_border_style(values->@(1), &node->border.rightStyle);
        @set_css_border_style(values->@(2), &node->border.bottomStyle);
        @set_css_border_style(values->@(3), &node->border.leftStyle);
        break;
    default:
        @set_css_border_style(values->@(0), &node->border.topStyle);
        @set_css_border_style(values->@(0), &node->border.rightStyle);
        @set_css_border_style(values->@(0), &node->border.bottomStyle);
        @set_css_border_style(values->@(0), &node->border.leftStyle);
        break;
    }
}

U0 @css_resolve_border_width(@html_dom_node* node, JsonArray* values)
{
    if (!node || !values || !values->length)
        return;
    switch (values->length) {
    case 2:
        @set_css_border_width(values->@(0), &node->border.top, &node->border.top.type);
        @set_css_border_width(values->@(0), &node->border.bottom, &node->border.bottom.type);
        @set_css_border_width(values->@(1), &node->border.left, &node->border.left.type);
        @set_css_border_width(values->@(1), &node->border.right, &node->border.right.type);
        break;
    case 3:
        @set_css_border_width(values->@(0), &node->border.top, &node->border.top.type);
        @set_css_border_width(values->@(1), &node->border.left, &node->border.left.type);
        @set_css_border_width(values->@(1), &node->border.right, &node->border.right.type);
        @set_css_border_width(values->@(2), &node->border.bottom, &node->border.bottom.type);
        break;
    case 4:
        @set_css_border_width(values->@(0), &node->border.top, &node->border.top.type);
        @set_css_border_width(values->@(1), &node->border.right, &node->border.right.type);
        @set_css_border_width(values->@(2), &node->border.bottom, &node->border.bottom.type);
        @set_css_border_width(values->@(3), &node->border.left, &node->border.left.type);
        break;
    default:
        @set_css_border_width(values->@(0), &node->border.top, &node->border.top.type);
        @set_css_border_width(values->@(0), &node->border.right, &node->border.right.type);
        @set_css_border_width(values->@(0), &node->border.bottom, &node->border.bottom.type);
        @set_css_border_width(values->@(0), &node->border.left, &node->border.left.type);
        break;
    }
}

U0 @css_resolve_border(@html_dom_node* node, JsonArray* values)
{
    if (!node || !values || !values->length)
        return;
    switch (values->length) {
    case 1:
        // style
        @set_css_border_style(values->@(0), &node->border.topStyle);
        @set_css_border_style(values->@(0), &node->border.rightStyle);
        @set_css_border_style(values->@(0), &node->border.bottomStyle);
        @set_css_border_style(values->@(0), &node->border.leftStyle);
        break;
    case 2:
        // determine if each value is width, style, or color
        break;
    case 3:
        // width, style, color
        @set_css_border_width(values->@(0), &node->border.top, &node->border.top.type);
        @set_css_border_width(values->@(0), &node->border.right, &node->border.right.type);
        @set_css_border_width(values->@(0), &node->border.bottom, &node->border.bottom.type);
        @set_css_border_width(values->@(0), &node->border.left, &node->border.left.type);
        @set_css_border_style(values->@(1), &node->border.topStyle);
        @set_css_border_style(values->@(1), &node->border.rightStyle);
        @set_css_border_style(values->@(1), &node->border.bottomStyle);
        @set_css_border_style(values->@(1), &node->border.leftStyle);
        @css_resolve_color(values->@(2), &node->border.topColor);
        @css_resolve_color(values->@(2), &node->border.rightColor);
        @css_resolve_color(values->@(2), &node->border.bottomColor);
        @css_resolve_color(values->@(2), &node->border.leftColor);
        break;
    default:
        break;
    }
}

U0 @css_resolve_margin(@html_dom_node* node, JsonArray* values)
{
    if (!node || !values || !values->length)
        return;
    switch (values->length) {
    case 2:
        @set_css_distance(values->@(0), &node->margin.top.value, &node->margin.top.type);
        @set_css_distance(values->@(0), &node->margin.bottom.value, &node->margin.bottom.type);
        @set_css_distance(values->@(1), &node->margin.left.value, &node->margin.left.type);
        @set_css_distance(values->@(1), &node->margin.right.value, &node->margin.right.type);
        break;
    case 3:
        @set_css_distance(values->@(0), &node->margin.top.value, &node->margin.top.type);
        @set_css_distance(values->@(1), &node->margin.left.value, &node->margin.left.type);
        @set_css_distance(values->@(1), &node->margin.right.value, &node->margin.right.type);
        @set_css_distance(values->@(2), &node->margin.bottom.value, &node->margin.bottom.type);
        break;
    case 4:
        @set_css_distance(values->@(0), &node->margin.top.value, &node->margin.top.type);
        @set_css_distance(values->@(1), &node->margin.right.value, &node->margin.right.type);
        @set_css_distance(values->@(2), &node->margin.bottom.value, &node->margin.bottom.type);
        @set_css_distance(values->@(3), &node->margin.left.value, &node->margin.left.type);
        break;
    default:
        @set_css_distance(values->@(0), &node->margin.top.value, &node->margin.top.type);
        @set_css_distance(values->@(0), &node->margin.right.value, &node->margin.right.type);
        @set_css_distance(values->@(0), &node->margin.bottom.value, &node->margin.bottom.type);
        @set_css_distance(values->@(0), &node->margin.left.value, &node->margin.left.type);
        break;
    }
}

U0 @css_resolve_padding(@html_dom_node* node, JsonArray* values)
{
    if (!node || !values || !values->length)
        return;
    switch (values->length) {
    case 2:
        @set_css_distance(values->@(0), &node->padding.top.value, &node->padding.top.type);
        @set_css_distance(values->@(0), &node->padding.bottom.value, &node->padding.bottom.type);
        @set_css_distance(values->@(1), &node->padding.left.value, &node->padding.left.type);
        @set_css_distance(values->@(1), &node->padding.right.value, &node->padding.right.type);
        break;
    case 3:
        @set_css_distance(values->@(0), &node->padding.top.value, &node->padding.top.type);
        @set_css_distance(values->@(1), &node->padding.left.value, &node->padding.left.type);
        @set_css_distance(values->@(1), &node->padding.right.value, &node->padding.right.type);
        @set_css_distance(values->@(2), &node->padding.bottom.value, &node->padding.bottom.type);
        break;
    case 4:
        @set_css_distance(values->@(0), &node->padding.top.value, &node->padding.top.type);
        @set_css_distance(values->@(1), &node->padding.right.value, &node->padding.right.type);
        @set_css_distance(values->@(2), &node->padding.bottom.value, &node->padding.bottom.type);
        @set_css_distance(values->@(3), &node->padding.left.value, &node->padding.left.type);
        break;
    default:
        @set_css_distance(values->@(0), &node->padding.top.value, &node->padding.top.type);
        @set_css_distance(values->@(0), &node->padding.right.value, &node->padding.right.type);
        @set_css_distance(values->@(0), &node->padding.bottom.value, &node->padding.bottom.type);
        @set_css_distance(values->@(0), &node->padding.left.value, &node->padding.left.type);
        break;
    }
}

Bool @apply_css_properties_to_node(@html_dom_node* node, JsonObject* properties)
{
    Bool should_display = TRUE;
    I64 i, j;
    JsonArray* values = NULL;
    JsonKey* font_key = NULL;
    JsonKey* key = properties->keys;
    U8 node_tmpnum_buf[16];
    U8* match_font_family = NULL;

    for (i = 0; i < properties->length; i++) {
        values = properties->@(key->name);

        if (!StrICmp(key->name, "display")) {
            if (!StrICmp(values->@(0), "none")) {
                should_display = FALSE;
                node->display = CSS_DISPLAY_NONE;
            } else {
                should_display = TRUE;
                node->display = CSS_DISPLAY_INLINE; // default to inline
                if (!StrICmp(values->@(0), "block")) {
                    node->display = CSS_DISPLAY_BLOCK;
                }
                if (!StrICmp(values->@(0), "inline")) {
                    node->display = CSS_DISPLAY_INLINE;
                }
                if (!StrICmp(values->@(0), "inline-block")) {
                    node->display = CSS_DISPLAY_INLINE_BLOCK;
                }
            }
        }

        if (!StrICmp(key->name, "background") || !StrICmp(key->name, "background-color")) {
            if (!StrICmp(values->@(0), "transparent")) {
                // FIXME: Actually do transparency
                node->backgroundColor = node->parentNode->backgroundColor;
            } else {
                @css_resolve_color(values->@(0), &node->backgroundColor);
            }
        }

        if (!StrICmp(key->name, "border")) {
            @css_resolve_border(node, values);
        }

        if (!StrICmp(key->name, "border-color")) {
            @css_resolve_border_color(node, values);
        }

        if (!StrICmp(key->name, "border-style")) {
            @css_resolve_border_style(node, values);
        }

        if (!StrICmp(key->name, "border-width")) {
            @css_resolve_border_width(node, values);
        }

        if (!StrICmp(key->name, "color")) {
            @css_resolve_color(values->@(0), &node->color);
        }

        if (!StrICmp(key->name, "margin")) {
            @css_resolve_margin(node, values);
        }

        if (!StrICmp(key->name, "margin-top")) {
            @set_css_distance(values->@(0), &node->margin.top.value, &node->margin.top.type);
        }
        if (!StrICmp(key->name, "margin-right")) {
            @set_css_distance(values->@(0), &node->margin.right.value, &node->margin.right.type);
        }
        if (!StrICmp(key->name, "margin-bottom")) {
            @set_css_distance(values->@(0), &node->margin.bottom.value, &node->margin.bottom.type);
        }
        if (!StrICmp(key->name, "margin-left")) {
            @set_css_distance(values->@(0), &node->margin.left.value, &node->margin.left.type);
        }

        if (!StrICmp(key->name, "padding")) {
            @css_resolve_padding(node, values);
        }

        if (!StrICmp(key->name, "padding-top")) {
            @set_css_distance(values->@(0), &node->padding.top.value, &node->padding.top.type);
        }
        if (!StrICmp(key->name, "padding-right")) {
            @set_css_distance(values->@(0), &node->padding.right.value, &node->padding.right.type);
        }
        if (!StrICmp(key->name, "padding-bottom")) {
            @set_css_distance(values->@(0), &node->padding.bottom.value, &node->padding.bottom.type);
        }
        if (!StrICmp(key->name, "padding-left")) {
            @set_css_distance(values->@(0), &node->padding.left.value, &node->padding.left.type);
        }

        if (!StrICmp(key->name, "width")) {
            @set_css_distance(values->@(0), &node->width, &node->widthDistanceType);
        }

        // FIXME: Handle max-width correctly
        if (!StrICmp(key->name, "max-width")) {
            @set_css_distance(values->@(0), &node->width, &node->widthDistanceType);
        }

        if (!StrICmp(key->name, "height")) {
            @set_css_distance(values->@(0), &node->height, &node->heightDistanceType);
        }

        if (!StrICmp(key->name, "text-align") && !StrICmp(values->@(0), "left"))
            node->textAlign = CSS_TEXT_ALIGN_LEFT;
        if (!StrICmp(key->name, "text-align") && !StrICmp(values->@(0), "center"))
            node->textAlign = CSS_TEXT_ALIGN_CENTER;
        if (!StrICmp(key->name, "text-align") && !StrICmp(values->@(0), "right"))
            node->textAlign = CSS_TEXT_ALIGN_RIGHT;

        if (!StrICmp(key->name, "text-decoration") || !StrICmp(key->name, "text-decoration-line")) {
            if (!StrICmp(values->@(0), "none")) {
                node->linethroughColor = 0;
                node->underlineColor = 0;
            }
            if (!StrICmp(values->@(0), "line-through")) {
                node->linethroughColor = node->color;
            }
            if (!StrICmp(values->@(0), "underline")) {
                node->underlineColor = node->color;
            }
        }

        //        if (!StrICmp(key->name, "line-height") && !StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "px")) {
        //            StrCpy(node_tmpnum_buf, values->@(0));
        //            node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
        //            node->fontSize = ToI64((Str2I64(node_tmpnum_buf) / 3) * 2);
        //        }

        if (!StrICmp(key->name, "font-size")) {
            StrCpy(node_tmpnum_buf, values->@(0));
            if (!StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "em")) {
                node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                node->fontSize = ToI64(Str2F64(node_tmpnum_buf) * RENDERER_DEFAULT_MAX_LINE_HEIGHT);
            }
            if (!StrICmp(values->@(0) + StrLen(values->@(0)) - 2, "pt")) {
                node_tmpnum_buf[StrLen(node_tmpnum_buf) - 2] = NULL;
                node->fontSize = ToI64(Str2F64(node_tmpnum_buf) * 1.33333333);
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
            for (j = 0; j < values->length; j++) {

                match_font_family = values->@(j);
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

        if (!StrICmp(key->name, "font-style")) {
            if (!StrICmp(values->@(0), "italic")) {
                node->italic = TRUE;
            }
        }
    css_continue_to_next_property:
        key = key->next;
    }
    return should_display;
}

Bool @css_selector_contains_combinator(U8* selector)
{
    U8* combinators = ">| +~";
    while (*selector) {
        if (StrOcc(combinators, *selector))
            return TRUE;
        ++selector;
    }
    return FALSE;
}

Bool @css_selector_is_compound_selector(U8* selector)
{
    U8* tokens = ".:[#";
    ++selector;
    while (*selector) {
        if (StrOcc(tokens, *selector))
            return TRUE;
        ++selector;
    }
    return FALSE;
}

Bool @node_matches_simple_selector(@html_dom_node* node, U8* selector)
{
    //"node: 0x%08x, selector: %s, ", node, selector;
    //"attributes: %s\n", Json.Stringify(node->attributes, erythros_mem_task);
    Bool match = FALSE;
    U8** node_classes = NULL;
    I64 node_classes_count = 0;
    U8 buffer[HTML_WORK_BUFFER_SIZE];
    U8* name = NULL;
    U8* value = NULL;

    I64 i = 0;
    U8 ptr_to_c_string[32];
    U8* ptr_to_md5_string = NULL;
    switch (*selector) {
    case '\xfe':
        StrPrint(ptr_to_c_string, "0x%08x", node);
        ptr_to_md5_string = md5_string(ptr_to_c_string, StrLen(ptr_to_c_string));
        if (!StrCmp(selector + 1, ptr_to_md5_string)) {
            match = TRUE;
        }
        Free(ptr_to_md5_string);
        return match;
    case '#':
        if (!node->attributes->@("id"))
            return FALSE;
        return !StrCmp(selector + 1, node->attributes->@("id"));
    case '.':
        if (!node->attributes->@("class"))
            return FALSE;
        if (!StrOcc(node->attributes->@("class"), ' ')) {
            if (!StrCmp(selector + 1, node->attributes->@("class"))) {
                match = TRUE;
            }
        } else {
            MemSet(buffer, 0, HTML_WORK_BUFFER_SIZE);
            StrCpy(buffer, node->attributes->@("class"));
            node_classes = String.Split(buffer, ' ', &node_classes_count);
            for (i = 0; i < node_classes_count; i++) {
                if (!StrCmp(selector + 1, node_classes[i])) {
                    match = TRUE;
                    i = node_classes_count;
                }
            }
            Free(node_classes);
        }
        return match;
    case '[':
        if (selector[StrLen(selector) - 1] == ']') {
            StrCpy(buffer, selector + 1);
            value = buffer + StrLen(buffer) - 1;
            while (StrOcc("'\"]", *value)) {
                *value = NULL;
                --value;
            }
            while (!StrOcc("'\"=", *value)) {
                --value;
            }
            name = value;
            ++value;
            while (StrOcc("'\"=", *value)) {
                *name = NULL;
                --name;
            }
            name = buffer;
            if (StrLen(name) && node->attributes->@(name) && !StrCmp(node->attributes->@(name), value)) {
                match = TRUE;
            }
        }
        return match;
    default:
        break;
    }
    // FIXME: Hack for link styles until we implement pseudo-classes
    if (String.EndsWith(":link", selector) && !StrICmp(node->tagName, "a")) {
        return TRUE;
    }
    return !StrICmp(node->tagName, selector);
}

Bool @node_matches_compound_selector(@html_dom_node* node, U8* compound_selector)
{
    U8 buffer[HTML_WORK_BUFFER_SIZE];
    U8* tokens = ".:[#";
    I64 i = 0;
    I64 j = 1;
    I64 length = StrLen(compound_selector);
    while (j && j < length) {
        if (StrOcc(tokens, compound_selector[j])) {
            MemSet(buffer, 0, length);
            MemCpy(buffer, compound_selector + i, j - i);
            i = j;
            //"nmcs: try: 0x%08x, %s\n", node, buffer;
            if (!@node_matches_simple_selector(node, buffer))
                return FALSE;
        }
        ++j;
    }
    //"nmcs: end: 0x%08x, %s\n", node, compound_selector + i;
    return @node_matches_simple_selector(node, compound_selector + i);
}

@html_dom_node* @ancestor_who_matches_compound_selector(@html_dom_node* node, U8* selector)
{
    while (node) {
        //"amcs: node: 0x%08x, selector: %s\n", node, selector;
        if (@node_matches_compound_selector(node, selector))
            return node;
        node = node->parentNode;
    }
    return NULL;
}

Bool @node_matches_selector_with_combinator(@html_dom_node* node, U8* selector_with_combinator)
{
    //"nmswc: node: 0x%08x, swc: %s\n", node, selector_with_combinator;
    // FIXME: We only handle the descendant combinator for now
    U8* ch = selector_with_combinator;
    while (*ch) {
        if (StrOcc(">|+~", *ch))
            return FALSE;
        ++ch;
    }

    @html_dom_node* ancestor = NULL;
    U8 buffer[HTML_WORK_BUFFER_SIZE];
    StrCpy(buffer, selector_with_combinator);
    String.Trim(buffer);
    U8* selector_for_ancestor = NULL;

    U8* selector_for_node = buffer + StrLen(buffer) - 1;
    while (*selector_for_node != ' ') {
        --selector_for_node;
    }

    ancestor = node->parentNode;
    selector_for_ancestor = selector_for_node;
    ++selector_for_node;

    if (!@node_matches_compound_selector(node, selector_for_node))
        return FALSE;

    // We matched the selector for node, now let's match the selectors for ancestors

    while (selector_for_ancestor > buffer) {
        // null terminate the selector for ancestor
        while (*selector_for_ancestor == ' ') {
            *selector_for_ancestor = NULL;
            --selector_for_ancestor;
        }
        // move selector for ancestor pointer to the left until we either:
        // 1) hit the beginning of the buffer, or
        // 2) hit whitespace
        while (selector_for_ancestor > buffer && (*selector_for_ancestor != ' ')) {
            --selector_for_ancestor;
        }
        if (*selector_for_ancestor == ' ')
            ++selector_for_ancestor;
        ancestor = @ancestor_who_matches_compound_selector(ancestor, selector_for_ancestor);
        if (!ancestor)
            return FALSE;
        --selector_for_ancestor;
    }
    // if we got here, we must be a match
    return TRUE;
}

Bool @node_matches_css_selector(@html_dom_node* node, U8* selector)
{
    // We need to handle combinators ("div ol li"), compound selectors "p.class#id", simple selectors

    // FIXME: Handle combinators
    if (@css_selector_contains_combinator(selector)) {
        return @node_matches_selector_with_combinator(node, selector);
        return FALSE;
    }

    // FIXME: Handle compound selectors
    if (@css_selector_is_compound_selector(selector)) {
        return @node_matches_compound_selector(node, selector);
        return FALSE;
    }

    return @node_matches_simple_selector(node, selector);
}

U0 @inherit_css_values_from_parent_node(@html_dom_node* node)
{
    if (node && node->parentNode) {
        node->backgroundColor = node->parentNode->backgroundColor;
        node->color = node->parentNode->color;
        node->linethroughColor = node->parentNode->linethroughColor;
        node->underlineColor = node->parentNode->underlineColor;
        node->fontFamily = node->parentNode->fontFamily;
        node->fontSize = node->parentNode->fontSize;
        node->fontWeight = node->parentNode->fontWeight;
        node->textAlign = node->parentNode->textAlign;
        node->italic = node->parentNode->italic;
    }
}

U0 @dump_node_indent(HtmlRenderer* renderer)
{
    I64 i;
    for (i = 0; i < renderer->indent; i++)
        "  ";
}

U0 @dump_distance_string(U8* out, F64 value, I64 type)
{
    switch (type) {
    case CSS_DISTANCE_UNDEFINED:
        StrCpy(out, "(undefined)");
        break;
    case CSS_DISTANCE_PIXELS:
        StrPrint(out, "%dpx", ToI64(value));
        break;
    case CSS_DISTANCE_EM:
        StrPrint(out, "%fem", value);
        break;
    case CSS_DISTANCE_PERCENT:
        StrPrint(out, "%f\xef\xbc\x85", value);
        break;
    case CSS_DISTANCE_AUTO:
        StrCpy(out, "auto");
        break;
    default:
        StrCpy(out, "(invalid)");
        break;
    }
}

U0 @dump_border_string(U8* out, F64 value, I64 type, I64 style, U32 color)
{
    @dump_distance_string(out, value, type);
    String.Append(out, " %s #%08x", border_style_values->@(style), color);
}

U0 @dump_node_info(@html_dom_node* node, HtmlRenderer* renderer, U8* comment = NULL)
{
    U8 buf[128];

    if (comment) {
        @dump_node_indent(renderer);
        "%s\n", comment;
    }

    @dump_node_indent(renderer);
    "<%s> display: %s, textAlign: %s, ",
        node->tagName, display_values->@(node->display), text_align_values->@(node->textAlign);
    @dump_distance_string(&buf, node->width, node->widthDistanceType);
    "width: %s, ", buf;
    @dump_distance_string(&buf, node->height, node->heightDistanceType);
    "height: %s, ", buf;
    "\n";

    @dump_node_indent(renderer);
    @dump_distance_string(&buf, node->margin.top.value, node->margin.top.type);
    "margin  - top: %s, ", buf;
    @dump_distance_string(&buf, node->margin.right.value, node->margin.right.type);
    "right: %s, ", buf;
    @dump_distance_string(&buf, node->margin.bottom.value, node->margin.bottom.type);
    "bottom: %s, ", buf;
    @dump_distance_string(&buf, node->margin.left.value, node->margin.left.type);
    "left: %s\n", buf;

    @dump_node_indent(renderer);
    @dump_distance_string(&buf, node->padding.top.value, node->padding.top.type);
    "padding - top: %s, ", buf;
    @dump_distance_string(&buf, node->padding.right.value, node->padding.right.type);
    "right: %s, ", buf;
    @dump_distance_string(&buf, node->padding.bottom.value, node->padding.bottom.type);
    "bottom: %s, ", buf;
    @dump_distance_string(&buf, node->padding.left.value, node->padding.left.type);
    "left: %s\n", buf;

    @dump_node_indent(renderer);
    @dump_border_string(&buf, node->border.top.value, node->border.top.type, node->border.topStyle, node->border.topColor);
    "border - top: %s, ", buf;
    @dump_border_string(&buf, node->border.right.value, node->border.right.type, node->border.rightStyle, node->border.rightColor);
    "right: %s, ", buf;
    @dump_border_string(&buf, node->border.bottom.value, node->border.bottom.type, node->border.bottomStyle, node->border.bottomColor);
    "bottom: %s, ", buf;
    @dump_border_string(&buf, node->border.left.value, node->border.left.type, node->border.leftStyle, node->border.leftColor);
    "left: %s\n", buf;

    @dump_node_indent(renderer);
    "bgcolor: #%08x, color: #%08x, fontFamily: \"%s\", fontSize: %dpx, fontWeight: %d\n", node->backgroundColor, node->color,
        node->fontFamily, node->fontSize, node->fontWeight;

    @dump_node_indent(renderer);
    "attributes: %s\n", Json.Stringify(node->attributes, erythros_mem_task);
}

Bool @apply_css_rules_to_node(@html_dom_node* node, HtmlRenderer* renderer)
{

    if (!node)
        return FALSE;

    I64 i, j;
    JsonObject* rule = NULL;
    JsonArray* matches = NULL;
    JsonObject* properties = NULL;
    U8* selector = NULL;
    Bool matched = FALSE;
    Bool should_display = TRUE;

    if (block_level_element_tag_names->contains(node->tagName)) {
        node->display = CSS_DISPLAY_BLOCK;
    }

    @inherit_css_values_from_parent_node(node);
    if (renderer->debug)
        @dump_node_info(node, renderer, "Inherited CSS values from parentNode:");

    for (i = 0; i < renderer->css_rules->length; i++) {
        rule = renderer->css_rules->@(i);
        matched = FALSE;
        if (rule->@("matches")) {
            matches = rule->@("matches");
            properties = rule->@("properties");
            for (j = 0; j < matches->length; j++) {
                selector = matches->@(j);
                if (@node_matches_css_selector(node, selector)) {
                    if (renderer->debug) {
                        @dump_node_indent(renderer);
                        "Matched selector: %s\n", selector;
                    }
                    matched = TRUE;
                    goto @css_rule_check_if_matched;
                }
            }
            @css_rule_check_if_matched : if (matched)
            {
                should_display = @apply_css_properties_to_node(node, properties);
                if (renderer->debug) {
                    @dump_node_indent(renderer);
                    "%s\n", Json.Stringify(properties, erythros_mem_task);
                    @dump_node_info(node, renderer, "CSS values after match:");
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

U0 @create_form_from_node(@html_dom_node* node, HtmlRenderer* renderer)
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

U0 @render_form_input_element(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !renderer || !node->attributes)
        return;

    U8* type = node->attributes->@("type");
    U8* value = node->attributes->@("value");
    I64 width;
    I64 height;

    if (!type)
        return;

    ButtonWidget* btn = NULL;
    TextInputWidget* input = NULL;
    CheckBoxWidget* cb = NULL;

    if (!StrICmp(type, "checkbox")) {
        if (!node->widthDistanceType)
            width = 14;
        if (!node->heightDistanceType)
            height = 14;
        cb = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CHECKBOX, U64_MAX, U64_MAX, width, height); // FIXME: Derive width/height
        cb->checked = node->attributes->@("checked");
        cb->data = node;
        node->attributes->set("cyberiaGuiWidget", cb, JSON_NUMBER);
        return;
    }

    if (!StrICmp(type, "button")) {
        if (!node->widthDistanceType)
            width = 64;
        if (!node->heightDistanceType)
            height = 16;
        btn = Gui.CreateWidget(renderer->win, WIDGET_TYPE_BUTTON, U64_MAX, U64_MAX, width, height); // FIXME: Derive width/height
        btn->data = node;
        StrCpy(&btn->text, @t(value, value, ""));
        node->attributes->set("cyberiaGuiWidget", btn, JSON_NUMBER);
        return;
    }

    if (!StrICmp(type, "submit")) {
        if (!node->widthDistanceType)
            width = 64;
        if (!node->heightDistanceType)
            height = 16;
        btn = Gui.CreateWidget(renderer->win, WIDGET_TYPE_BUTTON, U64_MAX, U64_MAX, width, height); // FIXME: Derive width/height
        btn->data = node;
        Gui.Widget.SetCallback(btn, "clicked", renderer->form_submit_callback);
        StrCpy(&btn->text, @t(value, value, "Submit"));
        node->attributes->set("cyberiaGuiWidget", btn, JSON_NUMBER);
        return;
    }

    if (!type || !StrICmp(type, "text")) {
        if (!node->widthDistanceType)
            width = 64;
        if (!node->heightDistanceType)
            height = 16;
        if (node->attributes->@("width")) {
            width = 8 * Str2I64(node->attributes->@("width"));
        }
        if (node->attributes->@("size")) {
            width = 8 * Str2I64(node->attributes->@("size"));
        }
        if (node->attributes->@("height")) {
            width = 16 * Str2I64(node->attributes->@("height"));
        }
        input = Gui.CreateWidget(renderer->win, WIDGET_TYPE_INPUT, U64_MAX, U64_MAX, width, height); // FIXME: Derive width/height
        input->data = node;
        StrCpy(&input->text, @t(value, value, ""));
        node->attributes->set("cyberiaGuiWidget", input, JSON_NUMBER);
        if (node->attributes->@("autofocus")) {
            renderer->win->focused_widget = input;
        }
        return;
    }

    if (!StrICmp(type, "password")) {
        if (!node->widthDistanceType)
            width = 64;
        if (!node->heightDistanceType)
            height = 16;
        if (node->attributes->@("width")) {
            width = 8 * Str2I64(node->attributes->@("width"));
        }
        if (node->attributes->@("size")) {
            width = 8 * Str2I64(node->attributes->@("size"));
        }
        if (node->attributes->@("height")) {
            width = 16 * Str2I64(node->attributes->@("height"));
        }
        input = Gui.CreateWidget(renderer->win, WIDGET_TYPE_INPUT, U64_MAX, U64_MAX, width, height); // FIXME: Derive width/height
        input->is_password = TRUE;
        input->data = node;
        StrCpy(&input->text, @t(value, value, ""));
        node->attributes->set("cyberiaGuiWidget", input, JSON_NUMBER);
        if (node->attributes->@("autofocus")) {
            renderer->win->focused_widget = input;
        }
        return;
    }
}

#define ADD_BYTE_TO_CODE_POINT_VALUE code_point = ((code_point << 6) | text[++i] & 0x3f);
#define ADD_TWO_BYTES_TO_CODE_POINT_VALUE ADD_BYTE_TO_CODE_POINT_VALUE ADD_BYTE_TO_CODE_POINT_VALUE
#define ADD_THREE_BYTES_TO_CODE_POINT_VALUE ADD_TWO_BYTES_TO_CODE_POINT_VALUE ADD_BYTE_TO_CODE_POINT_VALUE

I32* @I32_text_stream_from_utf8(U8* text, I64* count, HtmlRenderer* renderer)
{
    if (!text || !StrLen(text))
        return NULL;
    I64 i = 0;
    I64 j = 0;
    I32 ch;
    I32 code_point;
    I32* stream = CAlloc((StrLen(text) + 1) * sizeof(I32), renderer->task);
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

@html_dom_node* @self_or_ancestor_matches_tag_name(@html_dom_node* node, U8* tagName)
{
    while (node) {
        if (!StrICmp(node->tagName, tagName))
            return node;
        node = node->parentNode;
    }
    return NULL;
}

U8* @resolved_font_name_for_node(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !node->fontFamily || !StrLen(node->fontFamily))
        return NULL;

    U8* font_name_with_weight_applied = node->fontFamily;
    U8 buf[128];

    // Handle font weight
    if (node->fontWeight >= 700 && StrICmp(node->fontFamily + StrLen(node->fontFamily) - 4, "bold")) {
        StrPrint(buf, "%s Bold", node->fontFamily);
        if (Fonts->@(buf)) {
            font_name_with_weight_applied = StrNew(buf, renderer->task);
        }
    }

    // Handle italic
    if (node->italic) {
        StrPrint(buf, "%s Italic", font_name_with_weight_applied);
        if (Fonts->@(buf)) {
            return StrNew(buf, renderer->task);
        }
    }

    return font_name_with_weight_applied;
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
    I32* stream = @I32_text_stream_from_utf8(node->text, &code_point_count, renderer);

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
    U8* font_name = @resolved_font_name_for_node(node->parentNode, renderer);
    I64 underline_y_pos = -1;

    for (i = 0; i < fragment_count; i++) {
        if (fragments[i] && *fragments[i]) {
            text_width = @get_truetype_text_width(font_name, node->parentNode->fontSize, fragments[i]);
            if (text_width) {
                text_width += 3;
                fragment_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
                    U64_MAX, U64_MAX, 0, 0);
                fragment_widget->data = node;
                fragment_widget->ctx = NewContext2D(text_width, ToI64(node->parentNode->fontSize * 1.2))->fill(node->parentNode->backgroundColor)->text(font_name, 0, 0, node->parentNode->fontSize, node->parentNode->color, fragments[i]);

                if (node->parentNode->linethroughColor) {
                    fragment_widget->ctx->line(0, (fragment_widget->ctx->height / 2), fragment_widget->ctx->width - 1, (fragment_widget->ctx->height / 2), node->parentNode->linethroughColor);
                }

                if (node->parentNode->underlineColor) {
                    if (underline_y_pos < 0)
                        underline_y_pos = @get_truetype_baseline(font_name, node->parentNode->fontSize) + 3;
                    if (!(underline_y_pos < 0)) {
                        fragment_widget->ctx->line(0, underline_y_pos, fragment_widget->ctx->width - 1, underline_y_pos, node->parentNode->color);
                    }
                }

                if (renderer->debug && fragment_widget->ctx) {
                    fragment_widget->ctx->line(0, 0, fragment_widget->ctx->width - 1, 0, fragment_bounding_box_color);
                    fragment_widget->ctx->line(0, fragment_widget->ctx->height - 1, fragment_widget->ctx->width - 1, fragment_widget->ctx->height - 1, fragment_bounding_box_color);
                    fragment_widget->ctx->line(0, 0, 0, fragment_widget->ctx->height - 1, fragment_bounding_box_color);
                    fragment_widget->ctx->line(fragment_widget->ctx->width - 1, 0, fragment_widget->ctx->width - 1, fragment_widget->ctx->height - 1, fragment_bounding_box_color);
                }

                // FIXME: We use node->resolvedMargin.right.value as a dumb hack to add spacing between
                // list item numbers/bullets and adjacent text fragments, for now.
                fragment_widget->width = fragment_widget->ctx->width + node->resolvedMargin.right.value;
                fragment_widget->height = fragment_widget->ctx->height;
                fragment_widget->fast_copy = TRUE;
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
        @css_resolve_color(node->attributes->@("bgcolor"), &node->backgroundColor);
    }

    if (node->attributes->@("color")) {
        @css_resolve_color(node->attributes->@("color"), &node->color);
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

U0 @set_background_color_for_page(@html_dom_node* node, HtmlRenderer* renderer)
{
    renderer->background_color = node->backgroundColor;
    renderer->background_widget->color = renderer->background_color;
}

U0 @handle_tag_specific_functions(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!StrICmp(node->tagName, "body")) {
        @set_background_color_for_page(node, renderer);
    }

    if (!StrICmp(node->tagName, "form")) {
        @create_form_from_node(node, renderer);
    }

    if (!StrICmp(node->tagName, "li")) {
        // FIXME: We use node->resolvedMargin.right.value as a dumb hack to add spacing between
        // list item numbers/bullets and adjacent text fragments, for now.
        @html_dom_node* prepend_text_node = NULL;
        if (@self_or_ancestor_matches_tag_name(node, "ol")) {
            I64 ordered_list_index = @self_or_ancestor_matches_tag_name(node, "ol")->attributes->@("orderedListIndex") + 1;
            @self_or_ancestor_matches_tag_name(node, "ol")->attributes->set("orderedListIndex", ordered_list_index, JSON_NUMBER);
            prepend_text_node = @create_new_node("InternalTextNode", renderer->task);
            prepend_text_node->parentNode = node;
            prepend_text_node->text = CAlloc(16, renderer->task);
            StrPrint(prepend_text_node->text, "%d.", ordered_list_index);
            prepend_text_node->resolvedMargin.right.value = 8;
            node->children->prepend(prepend_text_node);
        } else if (@self_or_ancestor_matches_tag_name(node, "ul")) {
            prepend_text_node = @create_new_node("InternalTextNode", renderer->task);
            prepend_text_node->parentNode = node;
            prepend_text_node->text = StrNew("\xe2\x80\xa2", renderer->task);
            prepend_text_node->resolvedMargin.right.value = 8;
            node->children->prepend(prepend_text_node);
        }
    }

    if (!StrICmp(node->tagName, "strike")) {
        node->linethroughColor = node->color;
    }
}

U0 @render_internal_text_node(@html_dom_node* node, HtmlRenderer* renderer)
{
    U8* dump_text;
    node->text = @sanitize_node_text(renderer, node->text);
    if (!parent_nodes_excluded_from_text_rendering->contains(node->parentNode->tagName)) {
        if (renderer->debug) {
            @dump_node_indent(renderer);
            dump_text = StrNew(node->text);
            String.Trim(dump_text);
            "text: \"%s\"\n", dump_text;
        }
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

U0 @set_bordered_rect_from_resolved_node(@html_dom_node* node, BorderedRectWidget* widget)
{
    if (!node || !widget)
        return;
    if (node->widthDistanceType == CSS_DISTANCE_PIXELS) {
        widget->width = node->width;
    }
    if (node->heightDistanceType == CSS_DISTANCE_PIXELS) {
        widget->height = node->height;
    }

    widget->color = node->backgroundColor;

    if (node->border.top.value) {
        switch (node->border.top.type) {
        case CSS_DISTANCE_PIXELS:
            widget->top.size = node->border.top.value;
            widget->top.color = node->border.topColor;
            break;
        default:
            break;
        }
    }
    if (node->border.bottom.value) {
        switch (node->border.bottom.type) {
        case CSS_DISTANCE_PIXELS:
            widget->bottom.size = node->border.bottom.value;
            widget->bottom.color = node->border.bottomColor;
            break;
        default:
            break;
        }
    }
    if (node->border.left.value) {
        switch (node->border.left.type) {
        case CSS_DISTANCE_PIXELS:
            widget->left.size = node->border.left.value;
            widget->left.color = node->border.leftColor;
            break;
        default:
            break;
        }
    }
    if (node->border.right.value) {
        switch (node->border.right.type) {
        case CSS_DISTANCE_PIXELS:
            widget->right.size = node->border.right.value;
            widget->right.color = node->border.rightColor;
            break;
        default:
            break;
        }
    }
}

U0 @render_image_element(@html_dom_node* node, HtmlRenderer* renderer)
{
    Context2DWidget* img_widget = NULL;
    img_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_CONTEXT2D,
        U64_MAX, U64_MAX, node->width, node->height);
    if (node->widthDistanceType == CSS_DISTANCE_PIXELS && node->heightDistanceType == CSS_DISTANCE_PIXELS) {
        img_widget->width = node->width;
        img_widget->height = node->height;
    }
    img_widget->data = node;
    @renderer_append_image(renderer, img_widget);
}

U0 @render_node_list(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node || !renderer)
        return;

    ++renderer->indent;

    if (!StrICmp(node->tagName, "InternalTextNode")) {
        @render_internal_text_node(node, renderer);
        goto render_node_return;
    }

    if (!@apply_css_rules_to_node(node, renderer))
        goto render_node_return;

    @apply_attribute_values_to_node(node);
    @handle_tag_specific_functions(node, renderer);

    I64 i;
    BorderedRectWidget* block_widget = NULL;

    // If the element is an image,
    if (!StrICmp(node->tagName, "img")) {
        @render_image_element(node, renderer);
        // or, if the element is a form input element,
    } else if (!StrICmp(node->tagName, "input")) {
        @render_form_input_element(node, renderer);
        // or, if the element has CSS display: block, inline-block, insert a block widget for the element's opening tag
    } else if (node->display == CSS_DISPLAY_BLOCK || node->display == CSS_DISPLAY_INLINE_BLOCK) {
        block_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_BORDERED_RECT,
            U64_MAX, U64_MAX, 0, 0);
        // Try to set dimensions if we can
        @set_bordered_rect_from_resolved_node(node, block_widget);
        block_widget->data = node;
    }

    if (node->children->length) {
        for (i = 0; i < node->children->length; i++)
            @render_node_list(node->children->@(i), renderer);
    }

    // if the element has CSS display: block, inline-block, insert a block widget for the element's closing tag
    if (node->display == CSS_DISPLAY_BLOCK || node->display == CSS_DISPLAY_INLINE_BLOCK || !StrICmp(node->tagName, "br")) {
        block_widget = Gui.CreateWidget(renderer->win, WIDGET_TYPE_BORDERED_RECT,
            U64_MAX, U64_MAX, 0, 0);
        if (node->display == CSS_DISPLAY_BLOCK || node->display == CSS_DISPLAY_INLINE_BLOCK) {
            block_widget->width = -0xbeef;
            block_widget->height = -0xcafe;
        }
        block_widget->data = node;
    }

render_node_return:
    --renderer->indent;
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

        if (renderer->image_load_callback) {
            renderer->image_load_callback(renderer);
        }
        @fetch_next_image : image_list_item = image_list_item->next;
    }

    Free(buffer);
}