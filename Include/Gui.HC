U0 @gui_event_loop_handle_msg(IpcMessage* msg)
{
    Window* win = NULL;
    Widget* widget = NULL;
    Bool win_repaint = FALSE;
    // Bool widget_repaint = FALSE;
    switch (msg->type) {
    case CPZ_MSG_WIN_REPAINT:
    case CPZ_MSG_WIN_MOUSE_AT:
    case CPZ_MSG_WIN_MOUSE_WHEEL:
    case CPZ_MSG_WIN_LEFT_BTN_UP:
    case CPZ_MSG_WIN_LEFT_BTN_DOWN:
    case CPZ_MSG_WIN_RIGHT_BTN_UP:
    case CPZ_MSG_WIN_RIGHT_BTN_DOWN:
    case CPZ_MSG_WIN_KEY_PRESS:
        win = msg->payload;
        @umami_set_focused_and_hovered_widget(win, msg->type);
        break;
    case CPZ_MSG_WIN_WIDGET_DESTROY:
        widget = msg->payload;
        @gui_widget_destroy(widget);
        return;
    default:
        return;
    }
    if (!win)
        return;
    switch (msg->type) {
    case CPZ_MSG_WIN_REPAINT:
        win_repaint = TRUE;
        break;
    case CPZ_MSG_WIN_MOUSE_AT:
    case CPZ_MSG_WIN_MOUSE_WHEEL:
    case CPZ_MSG_WIN_LEFT_BTN_UP:
    case CPZ_MSG_WIN_LEFT_BTN_DOWN:
    case CPZ_MSG_WIN_RIGHT_BTN_UP:
    case CPZ_MSG_WIN_RIGHT_BTN_DOWN:
    case CPZ_MSG_WIN_KEY_PRESS:
        if (!win->explicit_repaint)
            win_repaint = TRUE;
        break;
    default:
        break;
    }
    switch (msg->type) {
    case CPZ_MSG_WIN_MOUSE_AT:
        if (win->callback.mouseat)
            win->callback.mouseat(win);
        break;
    case CPZ_MSG_WIN_KEY_PRESS:
        if (win->callback.keypress)
            win->callback.keypress(win, msg->i64);
        break;
    default:
        break;
    }
    if (win_repaint) {
        @gui_window_repaint(win, msg->type);
        Compositor.theme.window_repaint(win, msg->type);
        if (win->callback.repaint)
            win->callback.repaint(win);
    }
}

U0 @gui_event_loop(CTask* task)
{
    Fs->ipc = task->ipc;
    IpcMessage* msg;
    while (1) {
        msg = Ipc.MsgRecv();
        if (msg) {
            @gui_event_loop_handle_msg(msg);
            Free(msg);
        }
        Sleep(1);
    }
}

Ipc.InitQueue(Fs);
Spawn(&@gui_event_loop, Fs, Fs->task_name, 1);
System.Log(Fs, "Task running at 0x%08x", Fs);