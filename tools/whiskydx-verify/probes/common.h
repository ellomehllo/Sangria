/* Freestanding Win32 declarations for the D3D probes. No SDK headers exist
 * here, so only what the probes use is declared, with the x64 ABI layouts. */
#pragma once

typedef unsigned char BYTE;
typedef unsigned short WORD, WCHAR;
typedef unsigned int UINT, DWORD;
typedef int BOOL, INT;
typedef long HRESULT;
typedef long long LONGLONG;
typedef unsigned long long UINT_PTR, SIZE_T, ULONGLONG;
typedef long long LONG_PTR;
typedef void *HANDLE, *HWND, *HINSTANCE, *HMODULE, *HICON, *HCURSOR, *HBRUSH, *HMENU;
typedef LONG_PTR LRESULT, LPARAM;
typedef UINT_PTR WPARAM;
typedef struct { unsigned int Data1; unsigned short Data2, Data3; unsigned char Data4[8]; } GUID;
typedef union { struct { DWORD LowPart; long HighPart; } s; LONGLONG QuadPart; } LARGE_INTEGER;

#define IMPORT __declspec(dllimport)
#define S_OK 0
#define FAILED(hr) ((HRESULT)(hr) < 0)

typedef LRESULT (*WNDPROC)(HWND, UINT, WPARAM, LPARAM);
typedef struct {
    UINT cbSize, style; WNDPROC lpfnWndProc; int cbClsExtra, cbWndExtra;
    HINSTANCE hInstance; HICON hIcon; HCURSOR hCursor; HBRUSH hbrBackground;
    const WCHAR *lpszMenuName, *lpszClassName; HICON hIconSm;
} WNDCLASSEXW;
typedef struct { HWND hwnd; UINT message; WPARAM wParam; LPARAM lParam; DWORD time; long x, y; DWORD priv; } MSG;

IMPORT HMODULE GetModuleHandleW(const WCHAR *);
IMPORT void ExitProcess(UINT);
IMPORT BOOL QueryPerformanceCounter(LARGE_INTEGER *);
IMPORT BOOL QueryPerformanceFrequency(LARGE_INTEGER *);
IMPORT DWORD GetModuleFileNameW(HMODULE, WCHAR *, DWORD);
IMPORT HANDLE CreateFileW(const WCHAR *, DWORD, DWORD, void *, DWORD, DWORD, HANDLE);
IMPORT BOOL WriteFile(HANDLE, const void *, DWORD, DWORD *, void *);
IMPORT BOOL CloseHandle(HANDLE);
IMPORT const char *GetCommandLineA(void);

IMPORT unsigned short RegisterClassExW(const WNDCLASSEXW *);
IMPORT HWND CreateWindowExW(DWORD, const WCHAR *, const WCHAR *, DWORD, int, int, int, int, HWND, HMENU,
                            HINSTANCE, void *);
IMPORT BOOL ShowWindow(HWND, int);
IMPORT BOOL PeekMessageW(MSG *, HWND, UINT, UINT, UINT);
IMPORT BOOL TranslateMessage(const MSG *);
IMPORT LRESULT DispatchMessageW(const MSG *);
IMPORT LRESULT DefWindowProcW(HWND, UINT, WPARAM, LPARAM);
IMPORT void PostQuitMessage(int);
IMPORT int wsprintfA(char *, const char *, ...);

/* Calls method `index` of a COM object's vtable. */
#define VTBL(obj) (*(void ***)(obj))
#define COM(obj, index, type) ((type)VTBL(obj)[index])

void *memset(void *dst, int value, SIZE_T size);
void *memcpy(void *dst, const void *src, SIZE_T size);

/* Results file beside the executable: <exe without .exe>.results.txt */
static char g_results[4096];
static int g_results_len;
static WCHAR g_results_path[520];
static int g_quit;

static void results_add(const char *line) {
    int n = 0;
    while (line[n] && g_results_len + n < (int)sizeof(g_results) - 2) {
        g_results[g_results_len + n] = line[n];
        n++;
    }
    g_results_len += n;
    g_results[g_results_len++] = '\n';
}

static void results_flush(void) {
    /* GENERIC_WRITE, no sharing, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL */
    HANDLE file = CreateFileW(g_results_path, 0x40000000, 1, 0, 2, 0x80, 0);
    if (file == (HANDLE)-1) return;
    DWORD written;
    WriteFile(file, g_results, (DWORD)g_results_len, &written, 0);
    CloseHandle(file);
}

static void results_init(void) {
    DWORD len = GetModuleFileNameW(0, g_results_path, 500);
    if (len > 4) len -= 4; /* strip ".exe" */
    const char *suffix = ".results.txt";
    for (int i = 0; suffix[i]; i++) g_results_path[len++] = (WCHAR)suffix[i];
    g_results_path[len] = 0;
}

static void results_hr(const char *what, HRESULT hr) {
    char line[128];
    wsprintfA(line, "%s hr=0x%08x", what, (unsigned)hr);
    results_add(line);
}

static LRESULT window_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == 0x0010 /* WM_CLOSE */ || msg == 0x0002 /* WM_DESTROY */) {
        g_quit = 1;
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hwnd, msg, wp, lp);
}

static HWND make_window(const WCHAR *title, int width, int height) {
    static const WCHAR cls[] = {'P', 'r', 'o', 'b', 'e', 0};
    WNDCLASSEXW wc;
    memset(&wc, 0, sizeof(wc));
    wc.cbSize = sizeof(wc);
    wc.lpfnWndProc = window_proc;
    wc.hInstance = GetModuleHandleW(0);
    wc.lpszClassName = cls;
    RegisterClassExW(&wc);
    /* WS_OVERLAPPEDWINDOW | WS_VISIBLE */
    HWND hwnd = CreateWindowExW(0, cls, title, 0x10CF0000, 80, 80, width, height, 0, 0, wc.hInstance, 0);
    ShowWindow(hwnd, 1);
    return hwnd;
}

static void pump(void) {
    MSG msg;
    while (PeekMessageW(&msg, 0, 0, 0, 1 /* PM_REMOVE */)) {
        if (msg.message == 0x0012 /* WM_QUIT */) g_quit = 1;
        TranslateMessage(&msg);
        DispatchMessageW(&msg);
    }
}

static double now_seconds(void) {
    LARGE_INTEGER counter, freq;
    QueryPerformanceCounter(&counter);
    QueryPerformanceFrequency(&freq);
    return (double)counter.QuadPart / (double)freq.QuadPart;
}

/* Integer "secs=N" from the command line, or the fallback. */
static int arg_int(const char *key, int fallback) {
    const char *cmd = GetCommandLineA();
    for (const char *p = cmd; *p; p++) {
        int i = 0;
        while (key[i] && p[i] == key[i]) i++;
        if (!key[i]) {
            int value = 0;
            for (const char *q = p + i; *q >= '0' && *q <= '9'; q++) value = value * 10 + (*q - '0');
            return value;
        }
    }
    return fallback;
}

static void report_fps(long frames, double seconds) {
    char line[128];
    long hundredths = seconds > 0 ? (long)(frames * 100.0 / seconds) : 0;
    wsprintfA(line, "frames=%ld", frames);
    results_add(line);
    wsprintfA(line, "seconds=%ld.%02ld", (long)seconds, (long)(seconds * 100) % 100);
    results_add(line);
    wsprintfA(line, "avg_fps=%ld.%02ld", hundredths / 100, hundredths % 100);
    results_add(line);
}

int _fltused = 1;

#pragma clang optimize off
void *memset(void *dst, int value, SIZE_T size) {
    volatile unsigned char *d = dst;
    while (size--) *d++ = (unsigned char)value;
    return dst;
}
void *memcpy(void *dst, const void *src, SIZE_T size) {
    volatile unsigned char *d = dst;
    const unsigned char *s = src;
    while (size--) *d++ = *s++;
    return dst;
}
#pragma clang optimize on
