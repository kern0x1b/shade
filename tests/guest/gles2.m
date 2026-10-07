// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// gles2.m: guest test of the OpenGL ES 2 calls an image-processing engine makes, on an EAGL context
// drawing to a renderbuffer framebuffer.
//
// 1. glReadPixels returns what was drawn: the colour, the row order (rows count up from the lower
//    edge), the pack alignment, and a rectangle that reaches past the framebuffer.
//
// One line per case, "ok" or "FAIL <why>"; exits with the number of failures.
#import <Foundation/Foundation.h>
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

static int failures;

static void check(const char *name, BOOL good, const char *why)
{
    if (good) {
        printf("ok   %s\n", name);
    } else {
        printf("FAIL %s: %s\n", name, why);
        failures++;
    }
    fflush(stdout);
}

enum { side = 8 };

static void clearTo(float r, float g, float b, float a)
{
    glClearColor(r, g, b, a);
    glClear(GL_COLOR_BUFFER_BIT);
}

static BOOL near(const uint8_t *got, int r, int g, int b, int a)
{
    const int want[4] = {r, g, b, a};
    for (int i = 0; i < 4; i++) {
        int d = (int)got[i] - want[i];
        if (d < -1 || d > 1) return NO;
    }
    return YES;
}

static void expectRead(const char *name, int x, int y, int r, int g, int b, int a)
{
    uint8_t got[4] = {9, 9, 9, 9};
    glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, got);
    char why[96];
    snprintf(why, sizeof why, "pixel %d,%d read %d,%d,%d,%d, drew %d,%d,%d,%d (error 0x%x)", x, y,
             got[0], got[1], got[2], got[3], r, g, b, a, glGetError());
    check(name, near(got, r, g, b, a), why);
}

static void testReadPixels(void)
{
    clearTo(1.0f, 0.5f, 0.0f, 1.0f);
    expectRead("glReadPixels returns the cleared colour", 0, 0, 255, 128, 0, 255);
    expectRead("glReadPixels reads the far corner", side - 1, side - 1, 255, 128, 0, 255);

    // Rows count up from the lower edge: clear only rows 0 and 1, then look at both ends.
    clearTo(0.0f, 0.0f, 1.0f, 1.0f);
    glEnable(GL_SCISSOR_TEST);
    glScissor(0, 0, side, 2);
    clearTo(1.0f, 0.0f, 0.0f, 1.0f);
    glDisable(GL_SCISSOR_TEST);
    expectRead("glReadPixels row 0 is the lower edge", 3, 0, 255, 0, 0, 255);
    expectRead("glReadPixels row 1 is the lower edge", 3, 1, 255, 0, 0, 255);
    expectRead("glReadPixels row 2 is above it", 3, 2, 0, 0, 255, 255);
    expectRead("glReadPixels the top row is the upper edge", 3, side - 1, 0, 0, 255, 255);

    // A pack alignment of 8 starts the second row of a 3 pixel wide read at byte 16, not 12.
    uint8_t padded[64];
    memset(padded, 0x55, sizeof padded);
    glPixelStorei(GL_PACK_ALIGNMENT, 8);
    glReadPixels(0, 1, 3, 2, GL_RGBA, GL_UNSIGNED_BYTE, padded);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    BOOL rows = near(padded, 255, 0, 0, 255) && near(padded + 8, 255, 0, 0, 255)
        && near(padded + 16, 0, 0, 255, 255) && near(padded + 24, 0, 0, 255, 255);
    BOOL gap = padded[12] == 0x55 && padded[15] == 0x55;
    char why[96];
    snprintf(why, sizeof why, "row 0 starts %d,%d,%d,%d, row 1 at 16 starts %d,%d,%d,%d, gap byte %02x",
             padded[0], padded[1], padded[2], padded[3], padded[16], padded[17], padded[18], padded[19],
             padded[12]);
    check("glReadPixels honours the pack alignment", rows && gap, why);

    // The part of a rectangle outside the framebuffer is left as it was.
    clearTo(0.0f, 1.0f, 0.0f, 1.0f);
    uint8_t edge[4 * 4 * 4];
    memset(edge, 0x55, sizeof edge);
    glReadPixels(side - 2, side - 2, 4, 4, GL_RGBA, GL_UNSIGNED_BYTE, edge);
    BOOL inside = near(edge, 0, 255, 0, 255) && near(edge + 4, 0, 255, 0, 255)
        && near(edge + 16, 0, 255, 0, 255) && near(edge + 20, 0, 255, 0, 255);
    BOOL outside = edge[8] == 0x55 && edge[12] == 0x55 && edge[40] == 0x55 && edge[60] == 0x55;
    snprintf(why, sizeof why, "inside %d,%d,%d,%d outside bytes %02x %02x %02x %02x", edge[0], edge[1],
             edge[2], edge[3], edge[8], edge[12], edge[40], edge[60]);
    check("glReadPixels leaves what lies outside the framebuffer", inside && outside, why);

    glGetError();
    uint8_t unused[4];
    glReadPixels(0, 0, 1, 1, GL_RGB, GL_UNSIGNED_BYTE, unused);
    check("glReadPixels refuses a format it cannot give", glGetError() == GL_INVALID_OPERATION,
          "no GL_INVALID_OPERATION");
}

int main(void)
{
    @autoreleasepool {
        EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!context || ![EAGLContext setCurrentContext:context]) {
            check("an ES2 context", NO, "no context");
            return failures;
        }

        GLuint framebuffer = 0, renderbuffer = 0;
        glGenFramebuffers(1, &framebuffer);
        glGenRenderbuffers(1, &renderbuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, renderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA8_OES, side, side);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, renderbuffer);
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        char why[64];
        snprintf(why, sizeof why, "status 0x%x", status);
        check("a renderbuffer framebuffer is complete", status == GL_FRAMEBUFFER_COMPLETE, why);
        glViewport(0, 0, side, side);

        testReadPixels();
    }
    return failures;
}
