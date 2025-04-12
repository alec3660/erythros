#define STB_TRUETYPE_IMPLEMENTATION
#include "stb_truetype.h"

unsigned char* stbtt_RenderText(stbtt_fontinfo* info, int b_w, int b_h, int l_h, int* word)
{
    // https://github.com/justinmeiners/stb-truetype-example
    /* create a bitmap for the phrase */
    unsigned char* bitmap = calloc(b_w * b_h, sizeof(unsigned char));

    /* calculate font scaling */
    float scale = stbtt_ScaleForPixelHeight(info, l_h);

    int x = 0;

    int ascent, descent, lineGap;
    stbtt_GetFontVMetrics(info, &ascent, &descent, &lineGap);

    ascent = roundf(ascent * scale);
    descent = roundf(descent * scale);

    int i = 0;
    while (word[i]) {
        /* how wide is this character */
        int ax;
        int lsb;
        stbtt_GetCodepointHMetrics(info, word[i], &ax, &lsb);
        /* (Note that each Codepoint call has an alternative Glyph version which caches the work required to lookup the character word[i].) */

        /* get bounding box for character (may be offset to account for chars that dip above or below the line) */
        int c_x1, c_y1, c_x2, c_y2;
        stbtt_GetCodepointBitmapBox(info, word[i], scale, scale, &c_x1, &c_y1, &c_x2, &c_y2);

        /* compute y (different characters have different heights) */
        int y = ascent + c_y1;

        /* render character (stride and offset is important here) */
        int byteOffset = x + roundf(lsb * scale) + (y * b_w);
        stbtt_MakeCodepointBitmap(info, bitmap + byteOffset, c_x2 - c_x1, c_y2 - c_y1, b_w, scale, scale, word[i]);

        /* advance x */
        x += roundf(ax * scale);

        /* add kerning */
        int kern;
        kern = stbtt_GetCodepointKernAdvance(info, word[i], word[i + 1]);
        x += roundf(kern * scale);

        ++i;
    }

    return bitmap;
}

int main() { return 0; }
