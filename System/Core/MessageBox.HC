// Core component for MessageBox functions

Context2D* MESSAGEBOX_ICON_ERR = Image.FileToContext2D(
    "/Media/Themes/Umami/Icon/status/messagebox_critical.png");
Context2D* MESSAGEBOX_ICON_INFO = Image.FileToContext2D("/Media/Themes/Umami/Icon/status/messagebox_info.png");
Context2D* MESSAGEBOX_ICON_WARN = Image.FileToContext2D(
    "/Media/Themes/Umami/Icon/status/messagebox_warning.png");

Context2D* MESSAGEBOX_WIN_ICON_ERR = Image.FileToContext2D(
    "/Media/Themes/Umami/Icon/status/messagebox_critical_16x16.png");
Context2D* MESSAGEBOX_WIN_ICON_INFO = Image.FileToContext2D(
    "/Media/Themes/Umami/Icon/status/messagebox_info_16x16.png");
Context2D* MESSAGEBOX_WIN_ICON_WARN = Image.FileToContext2D(
    "/Media/Themes/Umami/Icon/status/messagebox_warning_16x16.png");

#define MESSAGEBOX_TYPE_ALERT 0
#define MESSAGEBOX_TYPE_ERROR 1
#define MESSAGEBOX_TYPE_INFO 2
#define MESSAGEBOX_TYPE_CONFIRM 3

JsonArray* @messagebox_default_info = Json.Parse("[\"OK\"]", Fs);
JsonArray* @messagebox_default_confirm = Json.Parse("[\"OK\",\"Cancel\"]", Fs);

U0 @messagebox_close_window(Window* window)
{
    Compositor.DestroyWindow(window);
}
U0 @messagebox_close_widget(Widget* widget)
{
    Compositor.DestroyWindow(widget->parent_win);
}

U0 @messagebox_msg(U8* str, I64 type, Context2D* win_icon, Context2D* icon,
    U64 callback = NULL, JsonArray* options = NULL)
{
    U64 flags = WIN_FLAGS_MOVABLE | WIN_FLAGS_ICON | WIN_FLAGS_TITLE_BAR | WIN_FLAGS_CLOSE_BUTTON;
    Window* win = Compositor.CreateWindow(0, 0, 320, 192, flags);
    Gui.Window.SetIcon(win, win_icon);
    switch (type) {
    case MESSAGEBOX_TYPE_ALERT:
        Gui.Window.SetTitle(win, "Alert");
        break;
    case MESSAGEBOX_TYPE_ERROR:
        Gui.Window.SetTitle(win, "Error");
        break;
    case MESSAGEBOX_TYPE_INFO:
        Gui.Window.SetTitle(win, "Info");
        break;
    case MESSAGEBOX_TYPE_CONFIRM:
        Gui.Window.SetTitle(win, "Confirm");
        break;
    }
    Context2DWidget* ctx_icon = Gui.CreateWidget(win, WIDGET_TYPE_CONTEXT2D, 8, 16, 24, 24);
    ctx_icon->ctx = icon;
    TextLabelWidget* lbl_text = Gui.CreateWidget(win, WIDGET_TYPE_LABEL, 40, 16, 192, 96);
    ButtonWidget* btn_ok = NULL;
    ButtonWidget* btn_cancel = NULL;

    Gui.Widget.SetText(lbl_text, str);
    Gui.Window.SetCallback(win, "close", callback);

    if (!callback) {
        callback = &@messagebox_close_widget;
    }

    if (options->length > 1) {
        btn_ok = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, (win->width / 2) - 80,
            win->height - 60, 64, 24);
        btn_cancel = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, (win->width / 2) + 16,
            win->height - 60, 64, 24);
        Gui.Widget.SetText(btn_ok, options->@(0));
        Gui.Widget.SetText(btn_cancel, options->@(1));
        Gui.Widget.SetCallback(btn_ok, "clicked", callback);
        Gui.Widget.SetCallback(btn_cancel, "clicked", callback);
        btn_ok->tag = TRUE;
        btn_cancel->tag = FALSE;
    } else {
        btn_ok = Gui.CreateWidget(win, WIDGET_TYPE_BUTTON, (win->width / 2) - 32,
            win->height - 60, 64, 24);
        Gui.Widget.SetText(btn_ok, options->@(0));
        Gui.Widget.SetCallback(btn_ok, "clicked", callback);
        btn_ok->tag = TRUE;
    }

    Gui.Window.Center(win);
    Gui.Window.SetFocus(win);
}

U0 @messagebox_alert(U8* str, U64 callback = NULL, JsonArray* options = NULL)
{
    if (!options || !options->length) {
        options = @messagebox_default_info;
    }
    @messagebox_msg(str, MESSAGEBOX_TYPE_ALERT, MESSAGEBOX_WIN_ICON_WARN,
        MESSAGEBOX_ICON_WARN, callback, options);
}

U0 @messagebox_error(U8* str, U64 callback = NULL, JsonArray* options = NULL)
{
    if (!options || !options->length) {
        options = @messagebox_default_info;
    }
    @messagebox_msg(str, MESSAGEBOX_TYPE_ERROR, MESSAGEBOX_WIN_ICON_ERR,
        MESSAGEBOX_ICON_ERR, callback, options);
}

U0 @messagebox_info(U8* str, U64 callback = NULL, JsonArray* options = NULL)
{
    if (!options || !options->length) {
        options = @messagebox_default_info;
    }
    @messagebox_msg(str, MESSAGEBOX_TYPE_INFO, MESSAGEBOX_WIN_ICON_INFO,
        MESSAGEBOX_ICON_INFO, callback, options);
}

U0 @messagebox_confirm(U8* str, U64 callback = NULL, JsonArray* options = NULL)
{
    if (!options || !options->length) {
        options = @messagebox_default_confirm;
    }
    @messagebox_msg(str, MESSAGEBOX_TYPE_CONFIRM, MESSAGEBOX_WIN_ICON_INFO,
        MESSAGEBOX_ICON_INFO, callback, options);
}

class @messagebox
{
    U0* (*Alert)(U8* str, U64 callback = NULL, JsonArray* options = NULL);
    U0* (*Error)(U8* str, U64 callback = NULL, JsonArray* options = NULL);
    U0* (*Info)(U8* str, U64 callback = NULL, JsonArray* options = NULL);
    U0* (*Confirm)(U8* str, U64 callback = NULL, JsonArray* options = NULL);
};

@messagebox MessageBox;
MessageBox.Alert = &@messagebox_alert;
MessageBox.Error = &@messagebox_error;
MessageBox.Info = &@messagebox_info;
MessageBox.Confirm = &@messagebox_confirm;

"messagebox ";