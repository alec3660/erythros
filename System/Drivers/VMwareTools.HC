// https://wiki.osdev.org/VMware_tools

#define VMWARE_MAGIC 0x564D5868
#define VMWARE_PORT 0x5658
#define VMWARE_PORTHB 0x5659

#define CMD_GETVERSION 10

#define CMD_ABSPOINTER_DATA 39
#define CMD_ABSPOINTER_STATUS 40
#define CMD_ABSPOINTER_COMMAND 41

#define ABSPOINTER_ENABLE 0x45414552
#define ABSPOINTER_RELATIVE 0xF5
#define ABSPOINTER_ABSOLUTE 0x53424152

class @vmware_cmd
{
    union {
        U32 ax;
        U32 magic;
    };
    union {
        U32 bx;
        I32 size;
    };
    union {
        U32 cx;
        U16 command;
    };
    union {
        U32 dx;
        U16 port;
    };
    U32 si;
    U32 di;
};

U0 @vmware_send(@vmware_cmd* cmd)
{
    U32 reg RAX reg_ax = cmd->ax;
    U32 reg RBX reg_bx = cmd->bx;
    U32 reg RCX reg_cx = cmd->cx;
    U32 reg RDX reg_dx = cmd->dx;
    U32 reg RSI reg_si = cmd->si;
    U32 reg RDI reg_di = cmd->di;
    reg_ax = VMWARE_MAGIC;
    reg_dx = VMWARE_PORT;
    asm {
        IN AX, DX
    }
    cmd->ax = reg_ax;
    cmd->bx = reg_bx;
    cmd->cx = reg_cx;
    cmd->dx = reg_dx;
    cmd->si = reg_si;
    cmd->di = reg_di;
}

Bool @vmware_backdoor_is_present()
{
    @vmware_cmd cmd;
    cmd.bx = ~VMWARE_MAGIC;
    cmd.command = CMD_GETVERSION;
    @vmware_send(&cmd);
    if (cmd.bx != VMWARE_MAGIC || cmd.ax == 0xFFFFFFFF) {
        return FALSE;
    }
    return TRUE;
}

U0 @vmware_ms_absolute()
{
    @vmware_cmd cmd;

    cmd.bx = ABSPOINTER_ENABLE;
    cmd.command = CMD_ABSPOINTER_COMMAND;
    @vmware_send(&cmd);

    cmd.bx = 0;
    cmd.command = CMD_ABSPOINTER_STATUS;
    @vmware_send(&cmd);

    cmd.bx = 1;
    cmd.command = CMD_ABSPOINTER_DATA;
    @vmware_send(&cmd);

    cmd.bx = ABSPOINTER_ABSOLUTE;
    cmd.command = CMD_ABSPOINTER_COMMAND;
    @vmware_send(&cmd);
}

U0 @vmware_handle_mouse()
{
    @vmware_cmd cmd;
    cmd.bx = 0;
    cmd.command = CMD_ABSPOINTER_STATUS;
    @vmware_send(&cmd);

    if (cmd.ax == 0xFFFF0000) {
        @vmware_ms_absolute;
        return;
    }

    if ((cmd.ax & 0xFFFF) < 4)
        return;

    cmd.bx = 4;
    cmd.command = CMD_ABSPOINTER_DATA;
    @vmware_send(&cmd);

    I32 buttons = (cmd.ax & 0xFFFF);
    I64 z = cmd.dx;
    if (z > 1) {
        z = -1;
    }

    MsSet(@lerp(cmd.bx, 0xffff, Display.width), @lerp(cmd.cx, 0xffff, Display.height), ms.pos.z + z);
    Mouse.x = @lerp(cmd.bx, 0xffff, Display.width);
    Mouse.y = @lerp(cmd.cx, 0xffff, Display.height);
    // MsSet((cmd.bx * Display.width) / 0xffff, (cmd.cx * Display.height) / 0xffff, ms.pos.z + z);
    ms.lb = buttons & 0x20;
    ms.rb = buttons & 0x10;
}

U0 @vmware_ms_nop() { }

U0 @vmware_ms_update()
{
    while (1) {
        @vmware_handle_mouse;
        Sleep(1);
    }
}

U0 @vmware_tools_init()
{
    if (!@vmware_backdoor_is_present) {
        return;
    }
    @patch_jmp_rel32(&WinMsUpdate, &@vmware_ms_nop);
    @vmware_ms_absolute;
    Spawn(&@vmware_ms_update, , "VMwareMsUpdateTask");
}

@vmware_tools_init;

"vmware-tools ";
