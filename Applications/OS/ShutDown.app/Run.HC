Gui.App();

U0 @shutdown_callback(U64 o)
{
    Window* win = NULL;
    if (o(Window*)->signature == WIN_SIGNATURE) {
        win = o;
    } else {
        if (o(Widget*)->tag) {
            System.PowerOff();
        } else {
            win = o(Widget*)->parent_win;
        }
    }
    Compositor.DestroyWindow(win);
    Kill(app_event_loop);
    Gui.Window.SetFocus(Compositor.GetWindowByTitle("Wallpaper"));
}

MessageBox.Confirm("Do you want to shut down this computer?", &@shutdown_callback);