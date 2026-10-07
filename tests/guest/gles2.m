// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// gles2.m: guest test of the OpenGL ES 2 calls an image-processing engine makes, on an EAGL context
// drawing to a renderbuffer framebuffer.
//
// 1. glReadPixels returns what was drawn: the colour, the row order (rows count up from the lower
//    edge), the pack alignment, and a rectangle that reaches past the framebuffer.
// 2. Shaders: GLSL ES 1.00 that is not valid is refused with a log, and a program whose varyings do
//    not match does not link. A valid program draws what its shaders say: uniforms of every shape,
//    varyings interpolated across the triangle, a texture read with its alpha intact, a texture
//    that an earlier pass drew, blending, discard and the attribute location glBindAttribLocation
//    chose.
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

static GLuint mainFramebuffer;

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

// Shaders ----------------------------------------------------------------------------------------

static const char *plainVertex =
    "attribute vec4 position;\n"
    "varying vec2 p;\n"
    "void main() { gl_Position = position; p = position.xy * 0.5 + 0.5; }\n";

static GLuint compile(GLenum type, const char *source, char *log, size_t logSize)
{
    GLuint shader = glCreateShader(type);
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    GLint status = 0;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &status);
    GLsizei length = 0;
    if (log) {
        log[0] = 0;
        glGetShaderInfoLog(shader, (GLsizei)logSize, &length, log);
    }
    if (!status) {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

// A linked program, or 0 with the reason in log.
static GLuint build(const char *vertexSource, const char *fragmentSource, char *log, size_t logSize)
{
    GLuint vertex = compile(GL_VERTEX_SHADER, vertexSource, log, logSize);
    GLuint fragment = compile(GL_FRAGMENT_SHADER, fragmentSource, log, logSize);
    if (!vertex || !fragment) return 0;
    GLuint program = glCreateProgram();
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glBindAttribLocation(program, 0, "position");
    glLinkProgram(program);
    GLint status = 0;
    glGetProgramiv(program, GL_LINK_STATUS, &status);
    if (log) {
        log[0] = 0;
        glGetProgramInfoLog(program, (GLsizei)logSize, NULL, log);
    }
    return status ? program : 0;
}

static const GLfloat quad[] = {-1, -1, 1, -1, -1, 1, 1, 1};

static void drawQuad(GLuint program)
{
    glUseProgram(program);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 0, quad);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

// The pixel at (x, y), with the OpenGL error checked, against a colour within two steps.
static void expectDrawn(const char *name, int x, int y, int r, int g, int b, int a)
{
    uint8_t got[4] = {9, 9, 9, 9};
    GLenum error = glGetError();
    glReadPixels(x, y, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, got);
    BOOL good = error == GL_NO_ERROR;
    const int want[4] = {r, g, b, a};
    for (int i = 0; i < 4; i++) {
        int d = (int)got[i] - want[i];
        if (d < -2 || d > 2) good = NO;
    }
    char why[112];
    snprintf(why, sizeof why, "pixel %d,%d read %d,%d,%d,%d, drew %d,%d,%d,%d (GL error 0x%x)", x, y,
             got[0], got[1], got[2], got[3], r, g, b, a, error);
    check(name, good, why);
}

static GLuint texture2x2(const uint8_t texels[16])
{
    GLuint texture = 0;
    glGenTextures(1, &texture);
    glBindTexture(GL_TEXTURE_2D, texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, texels);
    return texture;
}

static void testCompiling(void)
{
    char log[512];
    GLuint bad = compile(GL_FRAGMENT_SHADER, "precision mediump float;\nvoid main() { gl_FragColor = vec4(1.0) }\n", log, sizeof log);
    check("a shader with a syntax error does not compile", bad == 0, "compiled");
    check("and its log says where", strstr(log, "ERROR") != NULL && strstr(log, "0:2") != NULL, log);

    bad = compile(GL_FRAGMENT_SHADER, "precision mediump float;\nvoid main() { gl_FragColor = missing; }\n", log, sizeof log);
    check("a shader that names what is not declared does not compile", bad == 0 && strstr(log, "missing") != NULL, log);

    GLuint program = build(plainVertex,
        "precision mediump float;\nvarying vec3 p;\nvoid main() { gl_FragColor = vec4(p, 1.0); }\n", log, sizeof log);
    check("a varying declared with another type does not link", program == 0 && log[0] != 0, "linked or no log");

    // The vertex shader writes one float where the fragment shader reads four, and arrays of
    // other lengths: a link error, never a read or write past what the vertex shader wrote.
    program = build("attribute vec4 position;\nvarying float p;\nvoid main() { gl_Position = position; p = 1.0; }\n",
        "precision mediump float;\nvarying vec4 p;\nvoid main() { gl_FragColor = p; }\n", log, sizeof log);
    check("a varying float read as a vec4 does not link", program == 0 && strstr(log, "'p'") != NULL, log);

    program = build("attribute vec4 position;\nvarying vec4 p[2];\nvoid main() { gl_Position = position; p[0] = position; p[1] = position; }\n",
        "precision mediump float;\nvarying vec4 p[4];\nvoid main() { gl_FragColor = p[3]; }\n", log, sizeof log);
    check("a varying array of 2 read as an array of 4 does not link", program == 0 && strstr(log, "'p'") != NULL, log);

    program = build("attribute vec4 position;\nvarying vec4 p[4];\nvoid main() { gl_Position = position; p[3] = position; }\n",
        "precision mediump float;\nvarying vec4 p[2];\nvoid main() { gl_FragColor = p[1]; }\n", log, sizeof log);
    check("a varying array of 4 read as an array of 2 does not link", program == 0 && strstr(log, "'p'") != NULL, log);

    program = build(plainVertex,
        "precision mediump float;\nvarying vec2 p;\nvarying vec4 q;\nvoid main() { gl_FragColor = q + vec4(p, 0.0, 0.0); }\n", log, sizeof log);
    check("one varying of two missing does not link and the log names it", program == 0 && strstr(log, "'q'") != NULL, log);

    // A program that did not link cannot be used, and drawing with the one before it is an error.
    {
        GLuint vertex = compile(GL_VERTEX_SHADER, plainVertex, NULL, 0);
        GLuint fragment = compile(GL_FRAGMENT_SHADER,
            "precision mediump float;\nvarying vec3 p;\nvoid main() { gl_FragColor = vec4(p, 1.0); }\n", NULL, 0);
        GLuint broken = glCreateProgram();
        glAttachShader(broken, vertex);
        glAttachShader(broken, fragment);
        glBindAttribLocation(broken, 0, "position");
        glLinkProgram(broken);
        GLint linked = 1;
        glGetProgramiv(broken, GL_LINK_STATUS, &linked);
        (void)glGetError();
        glUseProgram(broken);
        check("glUseProgram on a program that did not link is GL_INVALID_OPERATION",
            linked == 0 && glGetError() == GL_INVALID_OPERATION, "no GL_INVALID_OPERATION");
        glUseProgram(0);
    }

    program = build(plainVertex,
        "precision mediump float;\nvarying vec2 elsewhere;\nvoid main() { gl_FragColor = vec4(elsewhere, 0.0, 1.0); }\n", log, sizeof log);
    check("a varying the vertex shader does not declare does not link", program == 0 && log[0] != 0, "linked or no log");

    program = build(plainVertex,
        "precision mediump float;\nvarying vec2 p;\nvoid main() { gl_FragColor = vec4(p, 0.0, 1.0); }\n", log, sizeof log);
    check("a program whose shaders agree links", program != 0, log);
}

static void testDrawing(void)
{
    char log[512];
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);

    // A uniform of each shape: glUniform4f, glUniform3f, glUniform2f, glUniform1f, glUniform4fv.
    GLuint program = build(plainVertex,
        "precision mediump float;\n"
        "uniform vec4 base;\nuniform vec3 add3;\nuniform vec2 add2;\nuniform float scale;\nuniform vec4 more[2];\n"
        "void main() { gl_FragColor = (base + vec4(add3, 0.0) + vec4(add2, 0.0, 0.0) + more[1]) * scale; }\n",
        log, sizeof log);
    check("the uniform program links", program != 0, log);
    if (!program) return;
    const GLuint uniformProgram = program;
    glUseProgram(program);
    glUniform4f(glGetUniformLocation(program, "base"), 0.1f, 0.1f, 0.1f, 0.5f);
    glUniform3f(glGetUniformLocation(program, "add3"), 0.1f, 0.2f, 0.3f);
    glUniform2f(glGetUniformLocation(program, "add2"), 0.2f, 0.1f);
    glUniform1f(glGetUniformLocation(program, "scale"), 2.0f);
    const GLfloat more[8] = {9, 9, 9, 9, 0.0f, 0.0f, 0.0f, 0.25f};
    glUniform4fv(glGetUniformLocation(program, "more"), 2, more);
    drawQuad(program);
    // (0.1 + 0.1 + 0.2, 0.1 + 0.2 + 0.1, 0.1 + 0.3, 0.5 + 0.25) * 2
    expectDrawn("uniforms of every shape reach the shader", 3, 3, 204, 204, 204, 255);

    // Varyings are interpolated: the centre of pixel (x, y) is ((x + 0.5) / 8, (y + 0.5) / 8), and the
    // rows count up from the lower edge.
    program = build(plainVertex,
        "precision mediump float;\nvarying vec2 p;\nvoid main() { gl_FragColor = vec4(p, 0.0, 1.0); }\n", log, sizeof log);
    drawQuad(program);
    expectDrawn("a varying is interpolated across the triangles, lower left", 0, 0, 16, 16, 0, 255);
    expectDrawn("a varying is interpolated across the triangles, lower right", side - 1, 0, 239, 16, 0, 255);
    expectDrawn("a varying is interpolated across the triangles, upper left", 0, side - 1, 16, 239, 0, 255);
    expectDrawn("a varying is interpolated across the triangles, middle", 4, 2, 144, 80, 0, 255);

    // Discard leaves what was there.
    clearTo(0.0f, 0.0f, 1.0f, 1.0f);
    program = build(plainVertex,
        "precision mediump float;\nvarying vec2 p;\nvoid main() { if (p.x < 0.5) discard; gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0); }\n",
        log, sizeof log);
    drawQuad(program);
    expectDrawn("a discarded fragment leaves the pixel as it was", 1, 4, 0, 0, 255, 255);
    expectDrawn("a fragment that is kept is drawn", 6, 4, 255, 0, 0, 255);

    // A texture, read through a matrix as Core Image reads one: the rows of a texture start at its lower edge.
    const uint8_t texels[16] = {255, 0, 0, 255,  0, 255, 0, 255,  0, 0, 255, 255,  255, 255, 255, 255};
    GLuint texture = texture2x2(texels);
    GLuint sampler = build(plainVertex,
        "precision highp float;\nvarying vec2 p;\nuniform lowp sampler2D image;\nuniform highp mat3 transform;\n"
        "void main() { highp vec3 c = vec3(p, 1.0) * transform; gl_FragColor = texture2D(image, c.xy); }\n",
        log, sizeof log);
    check("the texture program links", sampler != 0, log);
    if (!sampler) return;
    glUseProgram(sampler);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, texture);
    glUniform1i(glGetUniformLocation(sampler, "image"), 0);
    // Row vector times matrix: the identity, written column by column.
    const GLfloat identity[9] = {1, 0, 0, 0, 1, 0, 0, 0, 1};
    glUniformMatrix3fv(glGetUniformLocation(sampler, "transform"), 1, GL_FALSE, identity);
    drawQuad(sampler);
    expectDrawn("a texture is read, first texel at the lower left", 1, 1, 255, 0, 0, 255);
    expectDrawn("a texture is read, second texel at the lower right", 6, 1, 0, 255, 0, 255);
    expectDrawn("a texture is read, third texel at the upper left", 1, 6, 0, 0, 255, 255);
    expectDrawn("a texture is read, fourth texel at the upper right", 6, 6, 255, 255, 255, 255);

    // The matrix is applied as a row vector, so a translation sits in the first two columns' third row:
    // this one moves the lookup half a texture to the right.
    const GLfloat shift[9] = {1, 0, 0.5f, 0, 1, 0, 0, 0, 1};
    glUniformMatrix3fv(glGetUniformLocation(sampler, "transform"), 1, GL_FALSE, shift);
    drawQuad(sampler);
    expectDrawn("a matrix applied to a row vector moves the lookup", 1, 1, 0, 255, 0, 255);

    // A source with alpha is read with its alpha, not as opaque or as zero.
    const uint8_t half[16] = {128, 0, 0, 128,  128, 0, 0, 128,  128, 0, 0, 128,  128, 0, 0, 128};
    GLuint halfTexture = texture2x2(half);
    glBindTexture(GL_TEXTURE_2D, halfTexture);
    glUniformMatrix3fv(glGetUniformLocation(sampler, "transform"), 1, GL_FALSE, identity);
    clearTo(0.0f, 0.0f, 0.0f, 0.0f);
    drawQuad(sampler);
    expectDrawn("a half-alpha texel is read as drawn", 3, 3, 128, 0, 0, 128);

    // Premultiplied source over an opaque blue background.
    clearTo(0.0f, 0.0f, 1.0f, 1.0f);
    glEnable(GL_BLEND);
    glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
    drawQuad(sampler);
    glDisable(GL_BLEND);
    expectDrawn("blending with ONE, ONE_MINUS_SRC_ALPHA", 3, 3, 128, 0, 127, 255);

    // A pass that draws to a texture, and a second that reads it.
    GLuint target = 0, targetFramebuffer = 0;
    glGenTextures(1, &target);
    glBindTexture(GL_TEXTURE_2D, target);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, side, side, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &targetFramebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, targetFramebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, target, 0);
    check("a texture is a complete framebuffer target", glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "incomplete");
    clearTo(0.0f, 0.0f, 0.0f, 0.0f);
    GLuint gradient = build(plainVertex,
        "precision mediump float;\nvarying vec2 p;\nvoid main() { gl_FragColor = vec4(p.x, 0.0, p.y, 1.0); }\n", log, sizeof log);
    drawQuad(gradient);
    glBindFramebuffer(GL_FRAMEBUFFER, mainFramebuffer);
    clearTo(0.0f, 0.0f, 0.0f, 0.0f);
    glBindTexture(GL_TEXTURE_2D, target);
    drawQuad(sampler);
    expectDrawn("a texture drawn by one pass is read by the next", 7, 0, 239, 0, 16, 255);

    // The location glBindAttribLocation chose is the one the array is read from.
    GLuint moved = glCreateProgram();
    GLuint v = compile(GL_VERTEX_SHADER, plainVertex, NULL, 0);
    GLuint f = compile(GL_FRAGMENT_SHADER, "precision mediump float;\nvarying vec2 p;\nvoid main() { gl_FragColor = vec4(0.0, 1.0, 0.0, 1.0); }\n", NULL, 0);
    glAttachShader(moved, v);
    glAttachShader(moved, f);
    glBindAttribLocation(moved, 5, "position");
    glLinkProgram(moved);
    check("an attribute is where glBindAttribLocation put it", glGetAttribLocation(moved, "position") == 5, "wrong location");
    clearTo(0.0f, 0.0f, 0.0f, 1.0f);
    glUseProgram(moved);
    glEnableVertexAttribArray(5);
    glVertexAttribPointer(5, 2, GL_FLOAT, GL_FALSE, 0, quad);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    expectDrawn("and it is read from there", 3, 3, 0, 255, 0, 255);

    // Calls that do not fit the uniform.
    glGetError();
    check("an unknown uniform has no location", glGetUniformLocation(program, "nothing") == -1, "found one");
    glUseProgram(uniformProgram);
    glUniform1f(glGetUniformLocation(uniformProgram, "add2"), 1.0f);
    check("glUniform1f on a vec2 is refused", glGetError() == GL_INVALID_OPERATION, "no GL_INVALID_OPERATION");
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
        mainFramebuffer = framebuffer;
        glViewport(0, 0, side, side);

        testReadPixels();
        testCompiling();
        testDrawing();
    }
    return failures;
}
