#define CSS_DISPLAY_NONE 0
#define CSS_DISPLAY_BLOCK 1
#define CSS_DISPLAY_INLINE 2
#define CSS_DISPLAY_INLINE_BLOCK 3

#define CSS_DISTANCE_UNDEFINED 0
#define CSS_DISTANCE_PIXELS 1
#define CSS_DISTANCE_EM 2
#define CSS_DISTANCE_PERCENT 3
#define CSS_DISTANCE_AUTO 4

#define CSS_TEXT_ALIGN_LEFT 0
#define CSS_TEXT_ALIGN_CENTER 1
#define CSS_TEXT_ALIGN_RIGHT 2

#define CSS_TOKENIZER_STATE_CONSUME_MATCH 0
#define CSS_TOKENIZER_STATE_CONSUME_PROPERTY 1
#define CSS_TOKENIZER_STATE_CONSUME_VALUE 2
#define CSS_TOKENIZER_SKIP_AT_RULE 3
#define CSS_TOKENIZER_SKIP_COMMENT 4

U8* @css_named_colors_buffer = FileRead("M:/System/Libraries/Css/NamedColors.json");
JsonObject* @css_named_colors = Json.Parse(@css_named_colors_buffer, erythros_mem_task);
Free(@css_named_colors_buffer);

class @css_tokenizer
{
    U8* buffer;
    I64 pos;
    I64 size;
    I64 state;
    I64 previous_state;
    I64 in_quote_char;
    Bool in_paren;
    CFifoU8* match_fifo;
    CFifoU8* property_fifo;
    CFifoU8* value_fifo;
    JsonObject* current_rule;
    JsonArray* current_values;
    CTask* mem_task;
};

// U8* @custom_css_rules_buffer = FileRead("M:/System/Libraries/Css/CustomRules.json");
JsonObject* @custom_css_rules = Json.Parse("{}", erythros_mem_task);
// Free(@custom_css_rules_buffer);

U0 @css_init_current_values(@css_tokenizer* t)
{
    t->current_values = Json.CreateArray(erythros_mem_task);
}

U0 @css_init_current_rule(@css_tokenizer* t)
{
    t->current_rule = Json.CreateObject(erythros_mem_task);
    t->current_rule->set("matches", Json.CreateArray(erythros_mem_task), JSON_ARRAY);
    t->current_rule->set("properties", Json.CreateObject(erythros_mem_task), JSON_OBJECT);
}

U0 @css_init_tokenizer(@css_tokenizer* t, U8* buffer, I64 size, CTask* mem_task = NULL)
{
    t->buffer = buffer;
    t->pos = 0;
    t->in_quote_char = 0;
    t->in_paren = FALSE;
    t->size = size;
    t->state = CSS_TOKENIZER_STATE_CONSUME_MATCH;
    t->match_fifo = FifoU8New(1024);
    t->mem_task = mem_task;
    t->property_fifo = FifoU8New(1024);
    t->value_fifo = FifoU8New(1024);
    @css_init_current_rule(t);
}

Bool @css_try_append_match(@css_tokenizer* t)
{
    U8* match;
    if (FifoU8Cnt(t->match_fifo)) {
        match = @json_string_from_fifo(t->match_fifo, Fs);
        String.Trim(match);
        t->current_rule->a("matches")->append(match);
        return TRUE;
    }
    return FALSE;
}

Bool @css_try_append_value(@css_tokenizer* t)
{
    U8* value;
    if (FifoU8Cnt(t->value_fifo)) {
        value = @json_string_from_fifo(t->value_fifo, Fs);
        t->current_values->append(value);
        return TRUE;
    }
    return FALSE;
}

Bool @css_try_set_property(@css_tokenizer* t)
{
    U8* property;
    if (FifoU8Cnt(t->property_fifo)) {
        property = CAlloc(FifoU8Cnt(t->property_fifo) + 1, t->mem_task);
        while (FifoU8Cnt(t->property_fifo))
            FifoU8Rem(t->property_fifo, property + StrLen(property));
        t->current_rule->o("properties")->set(property, t->current_values, JSON_ARRAY);
        return TRUE;
    }
    return FALSE;
}

U0 @css_tokenize_and_create_rules_from_buffer(JsonArray* rules, U8* buffer, I64 size, CTask* mem_task = NULL)
{
    @css_tokenizer t;
    @css_init_tokenizer(&t, buffer, size, mem_task);
    I64 brace_depth = 0;
    JsonItem* item;
    U8 check_whitespace_char;
    while (t.pos < t.size) {
        I64 token = t.buffer[t.pos];
        switch (t.state) {
        case CSS_TOKENIZER_SKIP_COMMENT:
            if (token == '*' && t.buffer[t.pos + 1] == '/') {
                ++t.pos;
                t.state = t.previous_state;
                goto @css_tokenizer_continue;
            }
            break;
        case CSS_TOKENIZER_SKIP_AT_RULE:
            switch (token) {
            case '{':
                brace_depth++;
                break;
            case '}':
                brace_depth--;
                if (brace_depth <= 0) {
                    t.state = CSS_TOKENIZER_STATE_CONSUME_MATCH;
                    goto @css_tokenizer_continue;
                }
                break;
            default:
                break;
            }
            break;
        case CSS_TOKENIZER_STATE_CONSUME_VALUE:
            switch (token) {
            case '(':
            case ')':
                t.in_paren = T(token == '(', TRUE, FALSE);
                FifoU8Ins(t.value_fifo, token);
                goto @css_tokenizer_continue;
            case '\'':
            case '"':
                if (t.in_quote_char == token) {
                    t.in_quote_char = NULL;
                    FifoU8Ins(t.value_fifo, token);
                    goto @css_tokenizer_continue;
                }
                if (!t.in_quote_char) {
                    t.in_quote_char = token;
                }
                FifoU8Ins(t.value_fifo, token);
                goto @css_tokenizer_continue;
            case '/':
                if (t.in_quote_char) {
                    FifoU8Ins(t.value_fifo, token);
                    goto @css_tokenizer_continue;
                }
                if (t.buffer[t.pos + 1] == '*') {
                    ++t.pos;
                    t.previous_state = t.state;
                    t.state = CSS_TOKENIZER_SKIP_COMMENT;
                    goto @css_tokenizer_continue;
                }
            case ' ':
            case '\t':
            case '\r':
            case '\n':
                if (t.in_paren) {
                    goto @css_tokenizer_continue;
                }
            case ',':
                if (t.in_quote_char || t.in_paren) {
                    FifoU8Ins(t.value_fifo, token);
                    goto @css_tokenizer_continue;
                }
                if (FifoU8Cnt(t.value_fifo))
                    @css_try_append_value(&t);
                break;
            case '}':
                if (t.in_quote_char) {
                    FifoU8Ins(t.value_fifo, token);
                    goto @css_tokenizer_continue;
                }
                @css_try_append_value(&t);
                if (FifoU8Cnt(t.property_fifo))
                    @css_try_set_property(&t);
                if (t.current_rule->a("matches")->length) {
                    rules->append(t.current_rule);
                    @css_init_current_rule(&t);
                }
                t.state = CSS_TOKENIZER_STATE_CONSUME_MATCH;
                goto @css_tokenizer_continue;
            case ';':
                if (t.in_quote_char) {
                    FifoU8Ins(t.value_fifo, token);
                    goto @css_tokenizer_continue;
                }
                @css_try_append_value(&t);
                if (FifoU8Cnt(t.property_fifo))
                    @css_try_set_property(&t);
                t.state = CSS_TOKENIZER_STATE_CONSUME_PROPERTY;
                goto @css_tokenizer_continue;
            default:
                FifoU8Ins(t.value_fifo, token);
                break;
            }
            break;
        case CSS_TOKENIZER_STATE_CONSUME_PROPERTY:
            switch (token) {
            case '/':
                if (t.buffer[t.pos + 1] == '*') {
                    ++t.pos;
                    t.previous_state = t.state;
                    t.state = CSS_TOKENIZER_SKIP_COMMENT;
                    goto @css_tokenizer_continue;
                }
            case ' ':
            case '\t':
            case '\r':
            case '\n':
                if (FifoU8Cnt(t.property_fifo)) {
                    PrintErr("Invalid token in CSS property at pos %d, token: '%c'\n", t.pos, token);
                    return;
                }
                break;
            case '}':
                if (t.current_rule->a("matches")->length) {
                    rules->append(t.current_rule);
                    @css_init_current_rule(&t);
                }
                t.state = CSS_TOKENIZER_STATE_CONSUME_MATCH;
                goto @css_tokenizer_continue;
            case ':':
                if (!FifoU8Cnt(t.property_fifo)) {
                    PrintErr("CSS property is not defined at pos %d, token: '%c'\n", t.pos, token);
                    return;
                }
                @css_init_current_values(&t);
                t.state = CSS_TOKENIZER_STATE_CONSUME_VALUE;
                goto @css_tokenizer_continue;
            default:
                FifoU8Ins(t.property_fifo, token);
                break;
            }
            break;
        case CSS_TOKENIZER_STATE_CONSUME_MATCH:
            switch (token) {
            case '/':
                if (t.buffer[t.pos + 1] == '*') {
                    ++t.pos;
                    t.previous_state = t.state;
                    t.state = CSS_TOKENIZER_SKIP_COMMENT;
                    goto @css_tokenizer_continue;
                }
            case '@':
                t.state = CSS_TOKENIZER_SKIP_AT_RULE;
                goto @css_tokenizer_continue;
            case ' ':
            case '\t':
            case '\r':
            case '\n':
                FifoU8Last(t.match_fifo, &check_whitespace_char);
                if (check_whitespace_char != ' ') {
                    FifoU8Ins(t.match_fifo, ' ');
                }
                break;
            case ',':
                if (FifoU8Cnt(t.match_fifo))
                    @css_try_append_match(&t);
                break;
            case '{':
                @css_try_append_match(&t);
                if (!t.current_rule->a("matches")->length) {
                    PrintErr("CSS match string is not defined at pos %d, token: '%c'\n", t.pos, token);
                    return;
                }
                t.state = CSS_TOKENIZER_STATE_CONSUME_PROPERTY;
                goto @css_tokenizer_continue;
            default:
                FifoU8Ins(t.match_fifo, token);
                break;
            }
            break;
        }
        @css_tokenizer_continue : ++t.pos;
    }
    FifoU8Del(t.match_fifo);
    FifoU8Del(t.property_fifo);
    FifoU8Del(t.value_fifo);
}
