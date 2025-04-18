#define SHELL_HISTORY_LIMIT 1025
#define SHELL_INPUT_FIFO_SIZE 65536

class @shell_env_var
{
    @shell_env_var* prev;
    @shell_env_var* next;
    U8 key[256];
    U8 value[1024];
};

class @shell_autocomplete
{
    I64 depth;
    I64 length[8];
    U8*** entries;
};

class @shell_history
{
    I64 index;
    I64 limit;
    I64 pos;
    U8** entries;
};

class @shell_readline
{
    @shell_autocomplete autocomplete;
    @shell_history history;
};

class @shell
{
    CFifoU8* input;
    CFifoU8* output;
    CTask* task;
    Bool break;
    Bool exit;
    I64 answer;
    @shell_env_var* env;
    @shell_history history;
    @shell_readline readline;
    @session* session;
    U8 cwd[4096];
    U8 PS1[512];
    U8 PS2[512];
    U8 PS3[512];
    U8 PS4[512];
};

"shell ";