class @image
{
    Context2D* (*FileToContext2D)(U8* filepath);
    Context2D* (*BufferToContext2D)(U8* buffer, I64 size);
};

@image Image;

Context2D* @image_buffer_to_context2d(U8* buffer, I64 size)
{
    if (!buffer || !size) {
        return NULL;
    }
    I32 x;
    I32 y;
    I32 comp;
    I32 code = @stbi_info_from_memory(buffer, size, &x, &y, &comp);
    if (code != 1) {
        return NULL;
    }
    U8* pixels = @stbi_load_from_memory(buffer, size, &x, &y, &comp, 4);
    if (!pixels) {
        return NULL;
    }
    Context2D* ctx = CAlloc(sizeof(Context2D));
    ctx->width = x;
    ctx->height = y;
    ctx->bpp = 32;
    ctx->fb = pixels;
    I64 i;
    for (i = 0; i < x * y; i++) {
        ctx->fb(U32*)[i] = @image_pixel_flip_rgb_bgr(ctx->fb(U32*)[i]);
    }
    return ctx;
}

Context2D* @image_file_to_context2d(U8* filepath)
{
    if (!FileFind(filepath)) {
        return NULL;
    }
    I64 size = NULL;
    U8* buffer = FileRead(filepath, &size);
    if (!buffer || !size) {
        return NULL;
    }
    Context2D* ctx = @image_buffer_to_context2d(buffer, size);
    Free(buffer);
    return ctx;
}

Image.FileToContext2D = &@image_file_to_context2d;
Image.BufferToContext2D = &@image_buffer_to_context2d;

"image ";
