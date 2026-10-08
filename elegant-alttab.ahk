#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetName elegant-alttab
;@Ahk2Exe-SetDescription Simple Alt+Tab switcher with mood images
;@Ahk2Exe-SetVersion 1.1.1
;@Ahk2Exe-SetCopyright MIT`, tingwei
;@Ahk2Exe-SetMainIcon assets\peek-alttab.ico
; Alt+Tab limited to the focused monitor. Windows cloaks windows on other virtual desktops, and
; tiling WMs like GlazeWM cloak hidden workspaces, so this == "current desktop / workspace".
; Hold Alt, press Tab / Shift+Tab to move, release Alt to switch, Esc to cancel.

; ===== Settings: built-in defaults. Tray icon > Settings… saves overrides to settings.ini, which wins. =====
; (Or edit these, then right-click tray icon > Reload Script.)
FONT_NAME  := "Segoe UI"    ; ships with Windows; CJK titles fall back automatically
FONT_SIZE  := 16      ; text size in points
LIST_WIDTH := 700     ; list width in pixels
MAX_ROWS   := 15      ; longer lists scroll
PREVIEW_W  := 800    ; live preview width in pixels, right of the list (0 = no preview)
SEPARATOR  := "   —   "  ; between window title and process name
IMG_DIR    := "images" ; folder of the mood images, relative to this script
IMG_PREFIX := "chill" ; mood images in IMG_DIR: <prefix>_few.png, <prefix>_some.png, <prefix>_many.png
SOME_FROM  := 3       ; window counts: few = 1 .. SOME_FROM-1, some = SOME_FROM .. MANY_FROM-1,
MANY_FROM  := 8       ; many = MANY_FROM and up (2 <= SOME_FROM < MANY_FROM <= 30)
IMG_SIZE   := 100     ; mood image in the bottom-left corner, in pixels
IMG_ROWS   := 12      ; pane is tall enough that the list covers the image only beyond this many windows
WM_PROCESS := ""      ; optional: script exits when this process is gone, e.g. "glazewm.exe" ("" = never)
SettingsLoad()        ; settings.ini overrides (validated; see settings-panel.ahk)
; ==========================================================================

CoordMode "Mouse", "Screen"
if WM_PROCESS != ""
    SetTimer () => ProcessExist(WM_PROCESS) || ExitApp(), 2000

; Recency is tracked from foreground changes, not Z-order: tiling WMs re-tile with
; SetWindowPos, which reshuffles Z-order without anything being activated.
global mru := Map(), mruTick := 0   ; hwnd -> stamp of last activation (higher = newer)
for hwnd in WinGetList()            ; seed from Z-order so the first Alt+Tab is sensible
    mru[hwnd] := -A_Index
if a := WinExist("A")               ; the active window is the newest
    mru[DllCall("GetAncestor", "ptr", a, "uint", 3, "ptr")] := 0
global fgHook := CallbackCreate(OnForeground, "F", 7)
global fgHookH := DllCall("SetWinEventHook", "uint", 3, "uint", 3, "ptr", 0, "ptr", fgHook   ; EVENT_SYSTEM_FOREGROUND
    , "uint", 0, "uint", 0, "uint", 0, "ptr")                                               ; WINEVENT_OUTOFCONTEXT
OnExit((*) => (DllCall("UnhookWinEvent", "ptr", fgHookH), 0))   ; exit frees mru before it stops pumping events

global wins := [], rows := [], idx := 0, cycling := false   ; rows: [title, SEPARATOR process] per item
global g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale")
g.BackColor := "FAF6EF"              ; light ivory beige
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 33, "int*", 2, "uint", 4)          ; Win11 rounded corners
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 34, "uint*", 0xB4CBD9, "uint", 4)  ; warm tan border (BGR of D9CBB4)
g.SetFont("s" FONT_SIZE " c181614", FONT_NAME)   ; near-black text
global lb := g.AddListBox("w" LIST_WIDTH " r10 BackgroundFDFBF7 0x50 -E0x200")   ; pale cream, owner-drawn (DrawItem), no edge
OnMessage(0x2B, DrawItem)            ; WM_DRAWITEM
pw := Min(PREVIEW_W, A_ScreenWidth - LIST_WIDTH - 60)    ; must fit beside the list
global pv := pw > 0 ? g.AddText("x+10 yp w" pw " h" pw * 10 // 16) : 0   ; 16:10 area for the thumbnail
global thumb := 0                   ; DWM thumbnail handle of the highlighted window (0 = none)
g.AddText("xm ym Hidden", "Ag").GetPos(, , , &textH)   ; measure a line of the list font
SendMessage(0x1A0, 0, textH, lb)                       ; LB_SETITEMHEIGHT: owner-draw needs it set
; Mood images (few / some / many windows), scaled once. Added after the list with WS_CLIPSIBLINGS
; so the list covers them where they overlap. Missing file = no image.
DllCall("LoadLibrary", "str", "gdiplus")
si := Buffer(24, 0), NumPut("uint", 1, si)   ; GdiplusStartupInput
DllCall("gdiplus\GdiplusStartup", "ptr*", &gdipToken := 0, "ptr", si, "ptr", 0)
global imgs := []
for mood in ["few", "some", "many"]
    imgs.Push((hbm := ScaledBitmap(A_ScriptDir "\" IMG_DIR "\" IMG_PREFIX "_" mood ".png", IMG_SIZE))
        ? g.AddPicture("xm ym w" IMG_SIZE " h" IMG_SIZE " Hidden 0x4000000", "HBITMAP:" hbm) : 0)
DllCall("gdiplus\GdiplusShutdown", "ptr", gdipToken)
MOOD_NOTES := ["cozy ♡", "nice ✌", "too many…"]  ; caption beside the image, same order as imgs
g.SetFont("s" FONT_SIZE * 3 // 4 " c8C8174")     ; smaller, muted
global moodNote := g.AddText("xm ym r1 w" LIST_WIDTH - IMG_SIZE - 20 " Hidden 0x4000000")

!Tab::Step(1)
!+Tab::Step(-1)

#HotIf cycling
!Esc::Finish(false)
!Delete::CloseSelected()
!Down::
!Right::Step(1)
!Up::
!Left::Step(-1)
#HotIf

Step(dir) {
    global wins, idx, cycling
    started := false
    if !cycling {
        wins := CollectWindows()
        if wins.Length = 0
            return
        cycling := true
        idx := 0                      ; current window not in the list: first Tab picks item 1
        fg := DllCall("GetAncestor", "ptr", WinExist("A"), "uint", 3, "ptr")   ; GA_ROOTOWNER
        for i, hwnd in wins
            if hwnd = fg {
                wins.RemoveAt(i), wins.InsertAt(1, fg), idx := 1
                break
            }
        ShowList()
        started := true
    }
    idx := idx = 0 && dir < 0 ? wins.Length : Mod(idx - 1 + dir + wins.Length, wins.Length) + 1
    lb.Choose(idx)
    UpdatePreview(wins[idx])
    if started
        SetTimer WatchAlt, 20
}

WatchAlt() {
    if DllCall("GetAsyncKeyState", "int", 0x12, "short") >= 0   ; VK_MENU: OS state, covers injected Alt
        Finish(true)
}

Finish(activate) {
    global cycling
    SetTimer WatchAlt, 0
    UpdatePreview()
    g.Hide()
    cycling := false
    if activate && idx >= 1 && idx <= wins.Length && WinExist(wins[idx])
        WinActivate(wins[idx])
}

; Close the highlighted window and keep the list open, like native Alt+Tab.
CloseSelected() {
    global wins, idx
    hwnd := wins[idx]
    try WinClose(hwnd)
    Loop 20 {                     ; wait up to 1s; apps with a save prompt stay in the list
        if !IsOpen(hwnd)
            break
        Sleep 50
    }
    Critical                      ; WatchAlt must not run between `wins := alive` and the idx fix-up
    if !cycling                   ; Alt was released while waiting
        return
    alive := []
    for h in wins
        if IsOpen(h)
            alive.Push(h)
    wins := alive
    if wins.Length = 0
        return Finish(false)
    idx := Min(idx, wins.Length)
    ShowList()
    lb.Choose(idx)
    UpdatePreview(wins[idx])
}

; Show a live DWM thumbnail of src in the preview area; no src just drops the old one.
UpdatePreview(src := 0) {
    global thumb
    if thumb
        DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", thumb), thumb := 0
    if !pv || !src || DllCall("dwmapi\DwmRegisterThumbnail", "ptr", g.Hwnd, "ptr", src, "ptr*", &thumb)
        return thumb := 0           ; failed (HRESULT != 0): leave the area empty
    sz := 0
    DllCall("dwmapi\DwmQueryThumbnailSourceSize", "ptr", thumb, "int64*", &sz)
    sw := sz & 0xFFFFFFFF, sh := sz >> 32
    pv.GetPos(&x, &y, &w, &h)
    s := sw && sh ? Min(w / sw, h / sh, 1) : 0   ; keep aspect, never upscale
    tw := Round(sw * s), th := Round(sh * s)
    x += (w - tw) // 2, y += (h - th) // 2
    p := Buffer(48, 0)              ; DWM_THUMBNAIL_PROPERTIES
    NumPut("uint", 0xD, p, 0)       ; RECTDESTINATION | OPACITY | VISIBLE
    NumPut("int", x, "int", y, "int", x + tw, "int", y + th, p, 4)
    NumPut("uchar", 255, p, 36), NumPut("int", 1, p, 40)
    DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", thumb, "ptr", p)
}

; Image file -> sz x sz 32bpp HBITMAP (FitBitmap in gdip-helpers.ahk: bicubic, aspect kept).
; Transparent background = alpha kept. 0 = failed.
ScaledBitmap(file, sz) => (bm := FitBitmap(file, sz)) ? ToHbm(bm) : 0

; Owner-drawn list row: selection is a rounded pale-blue pill, process name muted.
DrawItem(wParam, lParam, *) {
    if NumGet(lParam, 24, "ptr") != lb.Hwnd         ; DRAWITEMSTRUCT.hwndItem
        return
    i := NumGet(lParam, 8, "int") + 1, dc := NumGet(lParam, 32, "ptr")
    l := NumGet(lParam, 40, "int"), t := NumGet(lParam, 44, "int")
    r := NumGet(lParam, 48, "int"), b := NumGet(lParam, 52, "int")
    rc := Buffer(16), NumPut("int", l, "int", t, "int", r, "int", b, rc)
    br := DllCall("CreateSolidBrush", "uint", 0xF7FBFD, "ptr")   ; BGR of FDFBF7, list background
    DllCall("FillRect", "ptr", dc, "ptr", rc, "ptr", br), DllCall("DeleteObject", "ptr", br)
    if i < 1 || i > rows.Length                     ; empty list: itemID = -1
        return true
    if NumGet(lParam, 16, "uint") & 1 {             ; ODS_SELECTED
        br := DllCall("CreateSolidBrush", "uint", 0xF2E6D6, "ptr")   ; BGR of D6E6F2
        ob := DllCall("SelectObject", "ptr", dc, "ptr", br, "ptr")
        op := DllCall("SelectObject", "ptr", dc, "ptr", DllCall("GetStockObject", "int", 8, "ptr"), "ptr")   ; NULL_PEN
        DllCall("RoundRect", "ptr", dc, "int", l + 4, "int", t + 2, "int", r - 3, "int", b - 1, "int", 14, "int", 14)
        DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("SelectObject", "ptr", dc, "ptr", op)
        DllCall("DeleteObject", "ptr", br)
    }
    DllCall("SetBkMode", "ptr", dc, "int", 1)       ; TRANSPARENT
    x := l + 14, xr := r - 14
    procW := TextWidth(dc, rows[i][2])
    titleW := Max(0, Min(TextWidth(dc, rows[i][1]), xr - x - procW))
    DrawCell(dc, rows[i][1], x, t, x + titleW, b, 0x141618)            ; BGR of 181614
    DrawCell(dc, rows[i][2], x + titleW, t, xr, b, 0x74818C)           ; BGR of 8C8174
    return true
}

DrawCell(dc, s, l, t, r, b, color) {
    rc := Buffer(16), NumPut("int", l, "int", t, "int", r, "int", b, rc)
    DllCall("SetTextColor", "ptr", dc, "uint", color)
    DllCall("DrawTextW", "ptr", dc, "wstr", s, "int", -1, "ptr", rc, "uint", 0x8824)   ; SINGLELINE|VCENTER|NOPREFIX|END_ELLIPSIS
}

TextWidth(dc, s) {
    rc := Buffer(16, 0)
    DllCall("DrawTextW", "ptr", dc, "wstr", s, "int", -1, "ptr", rc, "uint", 0xC20)    ; CALCRECT|SINGLELINE|NOPREFIX
    return NumGet(rc, 8, "int")
}

; Exists and visible (apps that "close to tray" only hide their window).
IsOpen(hwnd) => WinExist(hwnd) && DllCall("IsWindowVisible", "ptr", hwnd)

ShowList() {
    global rows := []
    titles := []
    for hwnd in wins {
        try rows.Push([WinGetTitle(hwnd), SEPARATOR WinGetProcessName(hwnd)])
        catch
            rows.Push(["(closed)", ""])
        titles.Push(rows[-1][1] rows[-1][2])
    }
    lb.Delete()
    lb.Add(titles)
    itemH := SendMessage(0x1A1, 0, 0, lb)   ; LB_GETITEMHEIGHT
    lb.Move(, , , Min(wins.Length, MAX_ROWS) * itemH + 4)   ; fit rows (+ border)
    for c in imgs                    ; hidden controls don't count for AutoSize
        if c
            c.Visible := false
    moodNote.Visible := false
    g.Show("Hide AutoSize")
    g.GetClientPos(, , &cw, &ch)
    minH := 2 * g.MarginY + IMG_ROWS * itemH + 4 + 8 + IMG_SIZE   ; IMG_ROWS rows + border + gap + image
    if ch < minH
        g.Show("Hide w" cw " h" (ch := minH))
    n := wins.Length, k := MoodOf(n)  ; few / some / many
    if c := imgs[k] {
        c.Move(, ch - g.MarginY - IMG_SIZE), c.Visible := true
        moodNote.Text := n " window" (n = 1 ? "" : "s") " · " MOOD_NOTES[k]
        moodNote.GetPos(, , , &nh)
        moodNote.Move(g.MarginX + IMG_SIZE + 12, ch - g.MarginY - (IMG_SIZE + nh) // 2), moodNote.Visible := true
    }
    g.GetPos(, , &w, &h)
    mi := Buffer(40, 0), NumPut("uint", 40, mi)
    DllCall("GetMonitorInfoW", "ptr", CurrentMonitor(), "ptr", mi)
    l := NumGet(mi, 20, "int"), t := NumGet(mi, 24, "int")   ; rcWork
    r := NumGet(mi, 28, "int"), b := NumGet(mi, 32, "int")
    g.Show("NA x" (l + (r - l - w) // 2) " y" (t + (b - t - h) // 2))
    WinSetTransparent(255, g.Hwnd)   ; fully opaque
}

; Monitor of the active window; falls back to the cursor's monitor (e.g. empty workspace).
CurrentMonitor() {
    hwnd := WinExist("A")
    if hwnd && !IsShell(hwnd)
        return DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
    MouseGetPos &x, &y
    return DllCall("MonitorFromPoint", "int64", (y << 32) | (x & 0xFFFFFFFF), "uint", 2, "ptr")
}

OnForeground(hook, event, hwnd, idObject, *) {
    global mruTick
    if idObject != 0 || !hwnd           ; OBJID_WINDOW only
        return
    mru[hwnd] := ++mruTick
    owner := DllCall("GetAncestor", "ptr", hwnd, "uint", 3, "ptr")   ; GA_ROOTOWNER: a dialog counts for its app
    if owner && owner != hwnd
        mru[owner] := mruTick
}

; Alt+Tab-eligible windows on the current monitor, most recently activated first.
CollectWindows() {
    mon := CurrentMonitor()
    out := []
    for hwnd in WinGetList() {          ; Z-order breaks ties between never-activated windows
        try {   ; a window may close mid-scan
            if IsSwitchable(hwnd) && DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr") = mon
                out.Push(hwnd)
        }
    }
    for hwnd in [mru*]                  ; forget closed windows (handles get reused)
        if !WinExist(hwnd)
            mru.Delete(hwnd)
    return SortByRecency(out)
}

; Stable insertion sort, newest first; lists are short.
SortByRecency(hwnds) {
    out := []
    for hwnd in hwnds {
        s := mru.Get(hwnd, -1e9), i := out.Length + 1
        while i > 1 && mru.Get(out[i - 1], -1e9) < s
            i--
        out.InsertAt(i, hwnd)
    }
    return out
}

IsShell(hwnd) {
    cls := WinGetClass(hwnd)
    return cls = "Progman" || cls = "WorkerW" || cls = "Shell_TrayWnd" || cls = "Shell_SecondaryTrayWnd"
}

IsSwitchable(hwnd) {
    if WinGetTitle(hwnd) = "" || IsShell(hwnd)
        return false
    ex := WinGetExStyle(hwnd)
    if ex & 0x08000000                                   ; WS_EX_NOACTIVATE
        return false
    if !(ex & 0x40000) {                                 ; not WS_EX_APPWINDOW
        if ex & 0x80                                     ; WS_EX_TOOLWINDOW
            return false
        if DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr")  ; owned window
            return false
    }
    cloaked := 0                                         ; DWMWA_CLOAKED: other desktops, hidden workspaces, background UWP
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloaked, "uint", 4)
    return !cloaked
}

; The Settings… panel and settings.ini (also brings the GDI+ helpers, FitBitmap among them).
#Include %A_LineFile%\..\settings-panel.ahk
