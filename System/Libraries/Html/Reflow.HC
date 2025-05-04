// FIXME: *** Handle margin collapsing ***

Bool reflow_debug = FALSE;

U0 @reflow_position_widget(Widget* widget, HtmlRenderer* renderer)
{
    widget->x = renderer->reflow.bounds.x1 + renderer->reflow.inline.x;
    widget->y = renderer->reflow.bounds.y1 + renderer->reflow.inline.y + renderer->scroll_y;
}

U0 @reflow_break_line(HtmlRenderer* renderer)
{
    renderer->reflow.inline.x = 0;
    renderer->reflow.inline.y += renderer->reflow.inline.max_line_height;
    renderer->reflow.inline.max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
}

U0 @reflow_break_line_if_not_enough_horizontal_space(Widget* widget, HtmlRenderer* renderer)
{
    if (renderer->reflow.parent) {
        @html_dom_node* parent_node = renderer->reflow.parent->data;
        if (parent_node && parent_node->display == CSS_DISPLAY_INLINE_BLOCK && parent_node->widthDistanceType == CSS_DISTANCE_UNDEFINED) {
            return;
        }
    }

    I32 combined_x = renderer->reflow.bounds.x1 + renderer->reflow.inline.x;
    if (combined_x > renderer->reflow.bounds.x2 - widget->width) {
        if (reflow_debug) {
            "*** not enough horizontal space, breaking line\n";
            "tag: %s\n", widget->data(@html_dom_node*)->tagName;
        }
        @reflow_break_line(renderer);
    }
}

U0 @reflow_break_line_if_inline_x_is_positive(HtmlRenderer* renderer)
{
    if (renderer->reflow.inline.x > 0) {
        @reflow_break_line(renderer);
    }
}

U0 @reflow_resolve_css_side(@html_dom_node* node, @css_side* parent_resolved_side, @css_side* resolved_side, @css_side* side)
{
    switch (side->type) {
    case CSS_DISTANCE_PIXELS:
        MemCpy(resolved_side, side, sizeof(@css_side));
        break;
    case CSS_DISTANCE_EM:
        resolved_side->value = ToI64(side->value * node->fontSize);
        resolved_side->type = CSS_DISTANCE_PIXELS;
        break;
    case CSS_DISTANCE_PERCENT:
        resolved_side->value = ToI64(parent_resolved_side->value * (100 / side->value));
        resolved_side->type = CSS_DISTANCE_PIXELS;
        break;
    default:
        break;
    }
}

U0 @reflow_collapse_margin_top(@html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node->display == CSS_DISPLAY_BLOCK) {
        return;
    }
    @html_dom_node* prev_node = renderer->reflow_previous_node;
    if (prev_node && prev_node->resolvedMargin.bottom.value > 0 && node->resolvedMargin.top.value > 0) {
        node->resolvedMargin.top.value = MaxI64(0, ToI64(node->resolvedMargin.top.value - prev_node->resolvedMargin.bottom.value));
    }
}

U0 @reflow_resolve_dynamic_margins(@html_dom_node* node, HtmlRenderer* renderer)
{
    @reflow_resolve_css_side(node, &node->parentNode->resolvedMargin.top, &node->resolvedMargin.top, &node->margin.top);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedMargin.right, &node->resolvedMargin.right, &node->margin.right);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedMargin.bottom, &node->resolvedMargin.bottom, &node->margin.bottom);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedMargin.left, &node->resolvedMargin.left, &node->margin.left);
    @reflow_collapse_margin_top(node, renderer);
}

U0 @reflow_resolve_dynamic_borders(@html_dom_node* node)
{
    @reflow_resolve_css_side(node, &node->parentNode->resolvedBorder.top, &node->resolvedBorder.top, &node->border.top);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedBorder.right, &node->resolvedBorder.right, &node->border.right);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedBorder.bottom, &node->resolvedBorder.bottom, &node->border.bottom);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedBorder.left, &node->resolvedBorder.left, &node->border.left);
}

U0 @reflow_resolve_dynamic_padding(@html_dom_node* node)
{
    @reflow_resolve_css_side(node, &node->parentNode->resolvedPadding.top, &node->resolvedPadding.top, &node->padding.top);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedPadding.right, &node->resolvedPadding.right, &node->padding.right);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedPadding.bottom, &node->resolvedPadding.bottom, &node->padding.bottom);
    @reflow_resolve_css_side(node, &node->parentNode->resolvedPadding.left, &node->resolvedPadding.left, &node->padding.left);
}

I64 @reflow_resolve_css_width_for_node(@html_dom_node* node)
{
    I64 resolved_width = 0;
    switch (node->widthDistanceType) {
    case CSS_DISTANCE_AUTO:
        while (!resolved_width) {
            node = node->parentNode;
            resolved_width = node->resolvedWidth;
        }
        return resolved_width;
    case CSS_DISTANCE_PIXELS:
        return ToI64(node->width);
    case CSS_DISTANCE_EM:
        return ToI64(node->width * RENDERER_DEFAULT_MAX_LINE_HEIGHT);
    case CSS_DISTANCE_PERCENT:
        return ToI64(node->parentNode->resolvedWidth * (100 / node->width));
    default:
        return 0;
    }
}

I64 @reflow_resolve_css_height_for_node(@html_dom_node* node)
{
    I64 resolved_height = 0;
    switch (node->heightDistanceType) {
    case CSS_DISTANCE_AUTO:
        while (!resolved_height) {
            node = node->parentNode;
            resolved_height = node->resolvedHeight;
        }
        return resolved_height;
    case CSS_DISTANCE_PIXELS:
        return ToI64(node->height);
    case CSS_DISTANCE_EM:
        return ToI64(node->height * RENDERER_DEFAULT_MAX_LINE_HEIGHT);
    case CSS_DISTANCE_PERCENT:
        return ToI64(node->parentNode->resolvedHeight * (100 / node->height));
    default:
        return 0;
    }
}

U0 @reflow_resolve_dynamic_width_and_height(@html_dom_node* node)
{
    node->resolvedWidth = @reflow_resolve_css_width_for_node(node);
    node->resolvedHeight = @reflow_resolve_css_height_for_node(node);
}

U0 @reflow_set_image_widget_dimensions_from_base(Context2DWidget* widget)
{
    @html_dom_node* node = widget->data;
    widget->width = node->resolvedWidth = node->width = widget->base->width;
    widget->height = node->resolvedHeight = node->height = widget->base->height;
    node->widthDistanceType = CSS_DISTANCE_PIXELS;
    node->heightDistanceType = CSS_DISTANCE_PIXELS;
}

U0 @reflow_set_image_widget_dimensions_from_context(Context2DWidget* widget)
{
    @html_dom_node* node = widget->data;
    widget->width = node->resolvedWidth = node->width = widget->ctx->width;
    widget->height = node->resolvedHeight = node->height = widget->ctx->height;
    node->widthDistanceType = CSS_DISTANCE_PIXELS;
    node->heightDistanceType = CSS_DISTANCE_PIXELS;
}

Bool @reflow_image_size_will_not_change(Context2DWidget* widget)
{
    @html_dom_node* node = widget->data;
    return (node->resolvedWidth && node->resolvedHeight && widget->width == node->resolvedWidth && widget->height == node->resolvedHeight);
}

U0 @reflow_set_image_widget_dimensions_from_node_width_and_height(Context2DWidget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    F64 scale_x = 0;
    F64 scale_y = 0;

    switch (node->widthDistanceType) {
    case CSS_DISTANCE_PIXELS:
        scale_x = node->width / ToF64(widget->base->width);
        break;
    case CSS_DISTANCE_PERCENT:
        scale_x = (ToF64(renderer->reflow.parent->width * (node->width / 100.0)) / ToF64(widget->base->width));
        return;
    default:
        break;
    }

    switch (node->heightDistanceType) {
    case CSS_DISTANCE_PIXELS:
        scale_y = node->height / ToF64(widget->base->height);
        break;
    case CSS_DISTANCE_PERCENT:
        scale_y = (ToF64(renderer->reflow.parent->height * (node->height / 100.0)) / ToF64(widget->base->height));
        return;
    default:
        break;
    }

    if (scale_x == 0.0 && scale_y == 0.0) {
        // Something went wrong, or unsupported distance type, use default values
        @reflow_set_image_widget_dimensions_from_base(widget);
    }

    if (scale_x == 1.0 && scale_y == 1.0) {
        // We are the same aspect ratio, use default values
        @reflow_set_image_widget_dimensions_from_base(widget);
    }

    widget->ctx = Scale2D(widget->base, scale_x, scale_y);
    @reflow_set_image_widget_dimensions_from_context(widget);
}

U0 @reflow_set_image_widget_dimensions_from_node_width(Context2DWidget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    F64 scale = 0;
    switch (node->widthDistanceType) {
    case CSS_DISTANCE_PIXELS:
        // If node width matches image width, set the values to the width and height of the image
        if (ToI64(node->width) == widget->base->width) {
            @reflow_set_image_widget_dimensions_from_base(widget);
            return;
        }
        scale = node->width / ToF64(widget->base->width);
        widget->ctx = Scale2D(widget->base, scale, scale);
        @reflow_set_image_widget_dimensions_from_context(widget);
        break;
    case CSS_DISTANCE_PERCENT:
        if (!renderer->reflow.parent->width)
            return;
        scale = (ToF64(renderer->reflow.parent->width * (node->width / 100.0)) / ToF64(widget->base->width));
        widget->ctx = Scale2D(widget->base, scale, scale);
        @reflow_set_image_widget_dimensions_from_context(widget);
        return;
    default:
        break;
    }
}

U0 @reflow_set_image_widget_dimensions_from_node_height(Context2DWidget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    F64 scale = 0;
    switch (node->heightDistanceType) {
    case CSS_DISTANCE_PIXELS:
        // If node width matches image height, set the values to the width and height of the image
        if (ToI64(node->height) == widget->base->height) {
            @reflow_set_image_widget_dimensions_from_base(widget);
            return;
        }
        scale = node->height / ToF64(widget->base->height);
        widget->ctx = Scale2D(widget->base, scale, scale);
        @reflow_set_image_widget_dimensions_from_context(widget);
        break;
    case CSS_DISTANCE_PERCENT:
        if (!renderer->reflow.parent->height)
            return;
        scale = (ToF64(renderer->reflow.parent->height * (node->height / 100.0)) / ToF64(widget->base->height));
        widget->ctx = Scale2D(widget->base, scale, scale);
        @reflow_set_image_widget_dimensions_from_context(widget);
        return;
    default:
        break;
    }
}

U0 @reflow_resolve_image_resizing(Context2DWidget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;

    if (!widget->base || !widget->base->width || !widget->base->height)
        return;

    if (@reflow_image_size_will_not_change(widget))
        return;

    // If node width and height are both zero, set their values to the width and height of the image
    if (!ToI64(node->width) && !ToI64(node->height)) {
        @reflow_set_image_widget_dimensions_from_base(widget);
        return;
    }

    // If the node width and height are both undefined type, set their values to the width and height of the image
    if (!node->widthDistanceType && !node->heightDistanceType) {
        @reflow_set_image_widget_dimensions_from_base(widget);
        return;
    }

    if (node->widthDistanceType && node->heightDistanceType) {
        @reflow_set_image_widget_dimensions_from_node_width_and_height(widget, renderer);
        return;
    }

    if (node->widthDistanceType && !node->heightDistanceType) {
        @reflow_set_image_widget_dimensions_from_node_width(widget, renderer);
        return;
    }

    if (!node->widthDistanceType && node->heightDistanceType) {
        @reflow_set_image_widget_dimensions_from_node_height(widget, renderer);
        return;
    }
}

U0 @reflow_resolve_dimensions_for_widget(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;

    if (node && !StrICmp(node->tagName, "img") && widget->type == WIDGET_TYPE_CONTEXT2D) {
        @reflow_resolve_image_resizing(widget, renderer);
        return;
    }

    // set a random bgcolor for the widget, so we can tell what is what during debugging
    if (reflow_debug) {
        switch (widget->type) {
        case WIDGET_TYPE_BORDERED_RECT:
            widget(BorderedRectWidget*)->color = Color(RandU16 & 0xff, RandU16 & 0xff, RandU16 & 0xff);
            break;
        case WIDGET_TYPE_RECT:
            widget(RectWidget*)->color = Color(RandU16 & 0xff, RandU16 & 0xff, RandU16 & 0xff);
            break;
        default:
            break;
        }
    }

    @reflow_resolve_dynamic_width_and_height(node);
    @reflow_resolve_dynamic_margins(node, renderer);
    @reflow_resolve_dynamic_borders(node);
    @reflow_resolve_dynamic_padding(node);
}

U0 @reflow_push(HtmlRenderer* renderer)
{
    if (reflow_debug) {
        "push: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
    ++renderer->reflow_index;
    MemCpy(&renderer->reflow_stack[renderer->reflow_index], &renderer->reflow, sizeof(@renderer_reflow));
}

U0 @reflow_pop(HtmlRenderer* renderer)
{
    if (reflow_debug) {
        "pop: before: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
    MemCpy(&renderer->reflow, &renderer->reflow_stack[renderer->reflow_index], sizeof(@renderer_reflow));
    --renderer->reflow_index;
    if (reflow_debug) {
        "pop: after: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
}

U0 @reflow_set_initial_values(HtmlRenderer* renderer)
{
    renderer->reflow.bounds.x1 = 0;
    renderer->reflow.bounds.x2 = renderer->background_widget->width;
    renderer->reflow.bounds.y1 = 0;
    renderer->reflow.bounds.y2 = renderer->win->height;
    renderer->reflow.inline.x = 0;
    renderer->reflow.inline.y = 0;
    renderer->reflow.inline.max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
    renderer->reflow.parent = NULL;
    renderer->reflow_index = -1;
    renderer->reflow_previous_node = NULL;
}

U0 @reflow_update_vertical_scrollbar(HtmlRenderer* renderer)
{
    // FIXME: this is glitchy and wrong
    VerticalScrollBarWidget* vscroll = renderer->vertical_scroll_widget;
    I32 origin_y = renderer->background_widget->y;
    I32 offset_y = origin_y;
    I32 minimum_vscroll_value = 0;
    if (vscroll && vscroll->max && vscroll->value) {
        minimum_vscroll_value = ToI64((vscroll->max * 1.0) / (vscroll->height * 1.0) * (16 * 1.0));
        offset_y -= vscroll->value - minimum_vscroll_value;
    }
    renderer->scroll_y = offset_y;
}

Bool @reflow_widget_has_closing_tag(Widget* widget)
{
    if (!widget)
        return FALSE;
    return (widget->width == -0xbeef && widget->height == -0xcafe);
}

U0 @reflow_apply_margins_to_bounds(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;

    I32 auto_width = 0;
    I32 border_left = 0;
    I32 border_right = 0;

    if (node->margin.left.type == CSS_DISTANCE_AUTO && node->margin.right.type == CSS_DISTANCE_AUTO) {
        switch (widget->type) {
        case WIDGET_TYPE_BORDERED_RECT:
            border_left = widget(BorderedRectWidget*)->left.size;
            border_right = widget(BorderedRectWidget*)->right.size;
            break;
        default:
            break;
        }
        auto_width = ((renderer->reflow.bounds.x2 - renderer->reflow.bounds.x1) / 2) - ((border_left + widget->width + border_right) / 2);
        renderer->reflow.bounds.x1 += auto_width;
        renderer->reflow.bounds.x2 -= auto_width;
    }

    switch (node->resolvedMargin.left.type) {
    case CSS_DISTANCE_UNDEFINED:
        break;
    case CSS_DISTANCE_PIXELS:
    default:
        renderer->reflow.bounds.x1 += ToI64(node->resolvedMargin.left.value);
        break;
    }

    switch (node->resolvedMargin.right.type) {
    case CSS_DISTANCE_UNDEFINED:
        break;
    case CSS_DISTANCE_PIXELS:
    default:
        renderer->reflow.bounds.x2 -= ToI64(node->resolvedMargin.right.value);
        break;
    }

    switch (node->resolvedMargin.top.type) {
    case CSS_DISTANCE_UNDEFINED:
        break;
    case CSS_DISTANCE_PIXELS:
    default:
        renderer->reflow.bounds.y1 += ToI64(node->resolvedMargin.top.value);
        break;
    }

    switch (node->resolvedMargin.bottom.type) {
    case CSS_DISTANCE_UNDEFINED:
        break;
    case CSS_DISTANCE_PIXELS:
    default:
        renderer->reflow.bounds.y2 -= ToI64(node->resolvedMargin.bottom.value);
        break;
    }
}

U0 @reflow_apply_border_and_padding_to_bounds(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    renderer->reflow.bounds.x1 += ToI64(node->resolvedBorder.left.value) + ToI64(node->resolvedPadding.left.value);
    renderer->reflow.bounds.x2 -= ToI64(node->resolvedBorder.right.value) + ToI64(node->resolvedPadding.right.value);
    renderer->reflow.bounds.y1 += ToI64(node->resolvedBorder.top.value) + ToI64(node->resolvedPadding.top.value);
    renderer->reflow.bounds.y2 -= ToI64(node->resolvedBorder.bottom.value) + ToI64(node->resolvedPadding.bottom.value);
}

U0 @reflow_reset_inline_position(HtmlRenderer* renderer)
{
    renderer->reflow.inline.x = 0;
    renderer->reflow.inline.y = 0;
}

U0 @reflow_set_previous_node(@html_dom_node* node, HtmlRenderer* renderer)
{
    renderer->reflow_previous_node = node;
}

U0 @reflow_clear_previous_node(HtmlRenderer* renderer)
{
    renderer->reflow_previous_node = NULL;
}

U0 @reflow_set_widget_dimensions(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;

    if (node->widthDistanceType == CSS_DISTANCE_UNDEFINED) {
        switch (node->display) {
        case CSS_DISPLAY_BLOCK:
            if (!(!StrICmp(node->tagName, "html") || !StrICmp(node->tagName, "body"))) {
                node->resolvedWidth = renderer->reflow.bounds.x2 - renderer->reflow.bounds.x1;
            }
            break;
        case CSS_DISPLAY_INLINE_BLOCK:
            node->resolvedWidth = renderer->reflow.inline.x;
            break;
        default:
            break;
        }
    }

    if (node->heightDistanceType == CSS_DISTANCE_UNDEFINED) {
        switch (node->display) {
        case CSS_DISPLAY_BLOCK:
        case CSS_DISPLAY_INLINE_BLOCK:
            @reflow_break_line_if_inline_x_is_positive(renderer);
            break;
        default:
            break;
        }
        if (reflow_debug) {
            "inline_y is: %d\n", renderer->reflow.inline.y;
        }
        node->resolvedHeight = renderer->reflow.inline.y;
    }

    widget->width = ToI64(node->resolvedPadding.left.value) + node->resolvedWidth + ToI64(node->resolvedPadding.right.value);
    widget->height = ToI64(node->resolvedPadding.top.value) + node->resolvedHeight + ToI64(node->resolvedPadding.bottom.value);
}

U0 @reflow_set_widget_as_parent_widget(Widget* widget, HtmlRenderer* renderer)
{
    renderer->reflow.parent = widget;
}

U0 @reflow_set_parent_widget_dimensions(HtmlRenderer* renderer)
{
    @reflow_set_widget_dimensions(renderer->reflow.parent, renderer);
}

U0 @reflow_apply_inline_x_to_bounds(HtmlRenderer* renderer)
{
    renderer->reflow.bounds.x1 += renderer->reflow.inline.x;
}

U0 @reflow_apply_inline_y_to_bounds(HtmlRenderer* renderer)
{
    renderer->reflow.bounds.y1 += renderer->reflow.inline.y;
}

U0 @reflow_apply_inline_to_bounds(HtmlRenderer* renderer)
{
    @reflow_apply_inline_x_to_bounds(renderer);
    @reflow_apply_inline_y_to_bounds(renderer);
}

U0 @reflow_apply_widget_height_to_inline(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;

    I32 height = widget->height;
    height += ToI64(node->resolvedMargin.top.value) + ToI64(node->resolvedMargin.bottom.value);
    height += ToI64(node->resolvedBorder.top.value) + ToI64(node->resolvedBorder.bottom.value);

    renderer->reflow.inline.y += height;
    if (reflow_debug) {
        "margins top/bottom: %d,%d\n", ToI64(node->resolvedMargin.top.value), ToI64(node->resolvedMargin.bottom.value);
        "borders top/bottom: %d,%d\n", ToI64(node->resolvedBorder.top.value), ToI64(node->resolvedBorder.bottom.value);
        "widget->height: %d\n", widget->height;
        "Added height: %d\n", height;

        "current: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
}

U0 @reflow_apply_widget_width_to_inline(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;

    I32 width = widget->height;
    width += ToI64(node->resolvedMargin.left.value) + ToI64(node->resolvedMargin.right.value);
    width += ToI64(node->resolvedBorder.left.value) + ToI64(node->resolvedBorder.right.value);

    renderer->reflow.inline.x += width;
    if (reflow_debug) {
        "margins left/right: %d,%d\n", ToI64(node->resolvedMargin.left.value), ToI64(node->resolvedMargin.right.value);
        "borders left/right: %d,%d\n", ToI64(node->resolvedBorder.left.value), ToI64(node->resolvedBorder.right.value);
        "widget->width: %d\n", widget->width;
        "Added width: %d\n", width;

        "current: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
}

U0 @reflow_apply_width_and_height_to_bounds(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    if (node->resolvedWidth) {
        renderer->reflow.bounds.x2 = renderer->reflow.bounds.x1 + node->resolvedWidth;
    }
    if (node->resolvedHeight) {
        renderer->reflow.bounds.y2 = renderer->reflow.bounds.y1 + node->resolvedHeight;
    }
}

U0 @reflow_begin_block(Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    if (reflow_debug) {
        "begin block: <%s>\n", node->tagName;
    }
    @reflow_break_line_if_inline_x_is_positive(renderer);
    @reflow_push(renderer);

    @reflow_apply_inline_y_to_bounds(renderer);
    @reflow_reset_inline_position(renderer);

    if (reflow_debug) {
        "apply inline y and reset: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }

    @reflow_set_widget_as_parent_widget(widget, renderer);
    @reflow_apply_margins_to_bounds(widget, renderer);
    @reflow_position_widget(widget, renderer);
    @reflow_apply_border_and_padding_to_bounds(widget, renderer);
    @reflow_apply_width_and_height_to_bounds(widget, renderer);
    @reflow_clear_previous_node(renderer);
}

U0 @reflow_end_block(Widget* widget, HtmlRenderer* renderer)
{
    renderer->calculated_page_height = MaxI64(renderer->calculated_page_height, renderer->reflow.bounds.y1 + renderer->reflow.inline.y);
    Widget* parent = renderer->reflow.parent;
    if (!parent)
        return;
    @html_dom_node* node = parent->data;
    if (reflow_debug) {
        "end block: </%s>\n", node->tagName;
    }
    @reflow_set_parent_widget_dimensions(renderer);
    @reflow_pop(renderer);
    @reflow_apply_widget_height_to_inline(parent, renderer);

    if (reflow_debug) {
        "apply widget height to inline: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
    @reflow_set_previous_node(node, renderer);
}

U0 @reflow_begin_inline_block(Widget* widget, HtmlRenderer* renderer)
{
    //    @reflow_begin_block(widget, renderer);

    @html_dom_node* node = widget->data;
    if (reflow_debug) {
        "begin inline-block: <%s>\n", node->tagName;
    }
    @reflow_push(renderer);

    @reflow_apply_inline_to_bounds(renderer);
    @reflow_reset_inline_position(renderer);

    if (reflow_debug) {
        "apply inline and reset: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }

    @reflow_set_widget_as_parent_widget(widget, renderer);
    @reflow_apply_margins_to_bounds(widget, renderer);
    @reflow_position_widget(widget, renderer);
    @reflow_apply_border_and_padding_to_bounds(widget, renderer);
    @reflow_apply_width_and_height_to_bounds(widget, renderer);
    @reflow_clear_previous_node(renderer);
}

U0 @reflow_end_inline_block(Widget* widget, HtmlRenderer* renderer)
{
    //    @reflow_end_block(widget, renderer);

    renderer->calculated_page_height = MaxI64(renderer->calculated_page_height, renderer->reflow.bounds.y1 + renderer->reflow.inline.y);
    Widget* parent = renderer->reflow.parent;
    @html_dom_node* node = parent->data;
    if (reflow_debug) {
        "end inline-block: </%s>\n", node->tagName;
    }
    @reflow_set_parent_widget_dimensions(renderer);
    @reflow_pop(renderer);
    @reflow_apply_widget_width_to_inline(parent, renderer);
    @reflow_apply_widget_height_to_inline(parent, renderer);

    if (reflow_debug) {
        "apply widget width to inline: bounds: %d/%d/%d/%d, inline: %d/%d, max_height: %d\n",
            renderer->reflow.bounds.x1, renderer->reflow.bounds.y1,
            renderer->reflow.bounds.x2, renderer->reflow.bounds.y2,
            renderer->reflow.inline.x, renderer->reflow.inline.y,
            renderer->reflow.inline.max_line_height;
    }
    @reflow_clear_previous_node(renderer);
}

U0 @reflow_break_line(HtmlRenderer* renderer)
{
    renderer->reflow.inline.x = 0;
    renderer->reflow.inline.y += renderer->reflow.inline.max_line_height;
    renderer->reflow.inline.max_line_height = RENDERER_DEFAULT_MAX_LINE_HEIGHT;
}

Bool @reflow_stop_calculating_offset(Widget* widget)
{
    @html_dom_node* node = widget->data;
    if (reflow_debug && @reflow_widget_has_closing_tag(widget)) {
        "stop: widget has closing tag: %s\n", node->tagName;
    }
    return (!node || node->display == CSS_DISPLAY_BLOCK || !StrICmp(node->tagName, "br") || @reflow_widget_has_closing_tag(widget));
}

I32 @reflow_calculate_text_align_offset(@window_widgets_list* wl, HtmlRenderer* renderer)
{
    I32 line_break_width = renderer->reflow.bounds.x2 - renderer->reflow.bounds.x1;
    if (renderer->reflow.parent) {
        @html_dom_node* parent_node = renderer->reflow.parent->data;
        if (parent_node && parent_node->display == CSS_DISPLAY_INLINE_BLOCK && parent_node->widthDistanceType == CSS_DISTANCE_UNDEFINED) {
            if (reflow_debug) {
                "set line_break_width to I32_MAX\n";
            }
            line_break_width = I32_MAX;
        }
    }
    I32 offset = wl->widget->width;
    wl = wl->next;
    while (wl && wl->widget && offset + wl->widget->width < line_break_width) {
        if (@reflow_stop_calculating_offset(wl->widget)) {
            wl = NULL;
        } else {
            offset += wl->widget->width;
            wl = wl->next;
        }
    }
    if (reflow_debug) {
        "offset is: %d\n", offset;
    }
    return offset;
}

U0 @reflow_handle_inline_text_align(@window_widgets_list* wl, @html_dom_node* node, HtmlRenderer* renderer)
{
    if (!node->textAlign)
        return;

    if (!renderer->reflow.inline.x) {
        I32 offset_x = @reflow_calculate_text_align_offset(wl, renderer);
        switch (node->textAlign) {
        case CSS_TEXT_ALIGN_CENTER:
            renderer->reflow.inline.x = (((renderer->reflow.bounds.x2 - renderer->reflow.bounds.x1) / 2) - (offset_x / 2));
            break;
        case CSS_TEXT_ALIGN_RIGHT:
            renderer->reflow.inline.x = (renderer->reflow.bounds.x2 - renderer->reflow.bounds.x1) - offset_x;
            break;
        default:
            break;
        }
    }
}

U0 @reflow_inherit_outer_bounds_if_zero_width(HtmlRenderer* renderer)
{
    I64 i = renderer->reflow_index - 1;
    if (renderer->reflow.bounds.x2 == renderer->reflow.bounds.x1) {
        renderer->reflow.parent->x = renderer->reflow_stack[i].bounds.x1;
        renderer->reflow.bounds.x2 = renderer->reflow_stack[i].bounds.x2;
        renderer->reflow.bounds.x1 = renderer->reflow_stack[i].bounds.x1;
    }
}

U0 @reflow_inline(@window_widgets_list* wl, Widget* widget, HtmlRenderer* renderer)
{
    @html_dom_node* node = widget->data;
    if (!StrICmp(node->tagName, "br")) {
        @reflow_break_line(renderer);
        return;
    }

    // FIXME: This terrible hack does the following:

    // - Inherit the parent (outer) block's bounds if our x1/x2 bounds are equal.
    // - Retry the reflow if we end up doing a line break.

    // Without this hack, we end up line breaking after every text fragment
    // if the containing block width is undefined and has auto margins or
    // text-align: center.

    @reflow_inherit_outer_bounds_if_zero_width(renderer);

    Bool continuing_reflow_inline_with_text_align = FALSE;
continue_reflow_inline_with_text_align:
    @reflow_handle_inline_text_align(wl, node, renderer);
    @reflow_break_line_if_not_enough_horizontal_space(widget, renderer);
    if (!renderer->reflow.inline.x && node->textAlign && !continuing_reflow_inline_with_text_align) {
        continuing_reflow_inline_with_text_align = TRUE;
        goto continue_reflow_inline_with_text_align;
    }
    @reflow_position_widget(widget, renderer);

    renderer->reflow.inline.x += widget->width;
    renderer->reflow.inline.max_line_height = MaxI64(widget->height, renderer->reflow.inline.max_line_height);
    @reflow_clear_previous_node(renderer);
}

U0 @reflow_set_hyperlink_if_needed(Widget* widget, HtmlRenderer* renderer)
{
    if (widget->callback.clicked)
        return;
    @html_dom_node* node = widget->data;
    if (@self_or_ancestor_matches_tag_name(node, "a")) {
        widget->pointer = renderer->link_pointer;
        Gui.Widget.SetCallback(widget, "clicked", renderer->link_callback);
    }
}

U0 @reflow_node_list(HtmlRenderer* renderer)
{
    if (!renderer || !renderer->win || !renderer->widgets_base)
        return;

    //"Reflow begin\n";

    Widget* widget = NULL;
    @html_dom_node* node = NULL;

    @window_widgets_list* wl = renderer->widgets_base->next;

    @reflow_update_vertical_scrollbar(renderer);
    @reflow_set_initial_values(renderer);
    @reflow_push(renderer);

    while (wl) {
        if (!wl->widget || !wl->widget->data) {
            goto reflow_next_wl;
        }

        widget = wl->widget;
        node = widget->data;

        if (!@reflow_widget_has_closing_tag(widget)) {
            @reflow_resolve_dimensions_for_widget(widget, renderer);
            @reflow_set_hyperlink_if_needed(widget, renderer);
        }

        switch (node->display) {
        case CSS_DISPLAY_BLOCK:
            if (@reflow_widget_has_closing_tag(widget)) {
                @reflow_end_block(widget, renderer);
            } else {
                @reflow_begin_block(widget, renderer);
            }
            goto reflow_next_wl;
        case CSS_DISPLAY_INLINE_BLOCK:
            if (@reflow_widget_has_closing_tag(widget)) {
                @reflow_end_inline_block(widget, renderer);
            } else {
                @reflow_begin_inline_block(widget, renderer);
            }
            goto reflow_next_wl;
        default:
            @reflow_inline(wl, widget, renderer);
            break;
        }

    reflow_next_wl:
        wl = wl->next;
    }

    wl = renderer->widgets_base->next;
    while (wl) {
        if (wl->widget && wl->widget->data) {
            node = wl->widget->data;
            if (!StrICmp(node->tagName, "body")) {
                renderer->calculated_page_height = MaxI64(node->resolvedHeight, renderer->calculated_page_height);
                break;
            }
        }
        wl = wl->next;
    }

    //"Reflow end";
}
