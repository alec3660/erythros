Gui.App();

U32 tos_palette_std[16] = {
    Color(0, 0, 0), Color(0, 0, 170), Color(0, 170, 0),
    Color(0, 170, 170), Color(170, 0, 0), Color(170, 0, 170),
    Color(170, 85, 0), Color(170, 170, 170), Color(85, 85, 85),
    Color(85, 85, 255), Color(85, 255, 85), Color(85, 255, 255),
    Color(255, 85, 85), Color(255, 85, 255), Color(255, 255, 85),
    Color(255, 255, 255)
};

I64 win_mouse_x = ms.pos.x;
I64 win_mouse_y = ms.pos.y;

CTask* templeos_winmgr_task = NULL;

U0 @templeos_close_callback(Window* win)
{
    Kill(templeos_winmgr_task);
    Compositor.UnregisterForGlobalInputEvents(win);
    Compositor.DestroyWindow(win);
    win = NULL;
    Exit;
}

Context2D* win_hide_pointer_ctx = NewContext2D(4, 4);

U0 @templeos_mouseat_callback(Window* win)
{
    win_mouse_x = win->mouse.x - 4;
    win_mouse_y = win->mouse.y - 24;
    if (win_mouse_x > 0 && win_mouse_x < 640 && win_mouse_y > 0 && win_mouse_y < 480) {
        win->pointer = win_hide_pointer_ctx;
    } else {
        win->pointer = NULL;
    }
}

U0 @templeos_keypress_callback(Window* win, I64 key)
{
    if (win != Compositor.active_win)
        return;
    if (!KeyDown(SC_GUI) && key) {
        if (KeyDown(SC_CURSOR_UP)) {
            PostMsg(sys_focus_task, MSG_KEY_DOWN_UP, 0, SC_CURSOR_UP);
            return;
        }
        if (KeyDown(SC_CURSOR_DOWN)) {
            PostMsg(sys_focus_task, MSG_KEY_DOWN_UP, 0, SC_CURSOR_DOWN);
            return;
        }
        if (KeyDown(SC_CURSOR_LEFT)) {
            PostMsg(sys_focus_task, MSG_KEY_DOWN_UP, 0, SC_CURSOR_LEFT);
            return;
        }
        if (KeyDown(SC_CURSOR_RIGHT)) {
            PostMsg(sys_focus_task, MSG_KEY_DOWN_UP, 0, SC_CURSOR_RIGHT);
            return;
        }
        // FIXME: Ctrl-key combinations
        if (KeyDown(SC_SHIFT)) {
            XTalkWait(sys_focus_task, "%c", SHIFT_KEY_SCAN_DECODE_TABLE(U8*)[key]);
        } else {
            XTalkWait(sys_focus_task, "%c", NORMAL_KEY_SCAN_DECODE_TABLE(U8*)[key]);
        }
    }
}

Context2D* icon = Image.FileToContext2D("window_icon_16x16.png");

Window* win = Compositor.CreateWindow(
    18, 554, 649, 508,
    (WIN_FLAGS_MOVABLE | WIN_FLAGS_ICON | WIN_FLAGS_TITLE_BAR | WIN_FLAGS_MIN_BUTTON | WIN_FLAGS_CLOSE_BUTTON),
    "TempleOS Window Manager", icon);

U0 Main()
{
    Gui.Window.Refresh(win);
    Compositor.RegisterForGlobalInputEvents(win);
    Gui.Window.SetCallback(win, "close", &@templeos_close_callback);
    Gui.Window.SetCallback(win, "keypress", &@templeos_keypress_callback);
    Gui.Window.SetCallback(win, "mouseat", &@templeos_mouseat_callback);

    Gui.Window.SetFocus(win);

    while (win) {
        if (win == Compositor.active_win) {
            win->flags |= WIN_FLAGS_NOFILL;
            if (IsSuspended(sys_winmgr_task)) {
                keydev.fp_ctrl_alt_cbs = tos_fp_cbs_enabled;
                Suspend(sys_winmgr_task, FALSE);
            }
            ms.pos.x = win_mouse_x;
            ms.pos.y = win_mouse_y;
        } else {
            if (!IsSuspended(sys_winmgr_task)) {
                keydev.fp_ctrl_alt_cbs = tos_fp_cbs_disabled;
                Suspend(sys_winmgr_task, TRUE);
            }
        }
        Sleep(1);
    }
}

U0 @templeos_winmgr_redraw()
{
    CDC* dc;
    I64 x, y;
    while (1) {
        dc = DCScrnCapture;
        for (y = 0; y < GR_HEIGHT; y++) {
            for (x = 0; x < GR_WIDTH; x++) {
                win->render_ctx->plot(x + 4, y + 24,
                    tos_palette_std[dc->body[(y * dc->width) + x]]);
                win->backing_store->plot(x + 4, y + 24,
                    tos_palette_std[dc->body[(y * dc->width) + x]]);
            }
        }
        DCDel(dc);
        Sleep(1);
    }
}

templeos_winmgr_task = Spawn(&@templeos_winmgr_redraw, , , 3);
// Adam("blkdev.boot_drv_let='C';WinFocus(User(\"WinMax;\n\"));\n");

Main;