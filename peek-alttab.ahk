#Requires AutoHotkey v2.0
#SingleInstance Force
;@Ahk2Exe-SetName peek-alttab
;@Ahk2Exe-SetDescription Frosted-glass Alt+Tab switcher
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
IMG_SIZE   := 250     ; image peeking over the pane's top-left edge, in pixels
PEEK_MIN   := 0.72    ; share of the image's art (transparent padding ignored) above the pane at 1 window,
PEEK_MAX   := 0.95    ; rising evenly to this at MANY_FROM + 4 windows and beyond (0.30 .. 1.00)
WM_PROCESS := ""      ; optional: script exits when this process is gone, e.g. "glazewm.exe" ("" = never)
SettingsLoad()        ; settings.ini overrides (validated; see settings-panel.ahk)
; ==========================================================================

; ===== Glass look (opaque frosted pane lit from the bottom-left; colours RRGGBB, alphas 0-255) =====
BASE_TOP    := "FCF9F4", BASE_MID := "FAF6EF", BASE_BOT := "F4ECDE"   ; vertical base gradient
BORDER      := "D9CBB4"                 ; DWM 1px outer border
LIGHT_ANGLE := 315                      ; GDI+ degrees clockwise from +x: 315 = bottom-left -> top-right
SHADE_RGB   := "E3D2B4", SHADE_A := 64  ; counter-shade: ellipse centred on the top-right corner,
SHADE_RX    := 0.60, SHADE_RY := 1.00   ; radii as fractions of the pane's width / height
SHEEN_A     := 80, SHEEN_H := 0.35      ; white top sheen, gone by SHEEN_H of the height
BLOOM_RX    := 0.45, BLOOM_RY := 0.90   ; bottom-left bloom ellipse; stops: [rgb, alpha, distance from centre 0-1]
BLOOM       := [["FFFFFF", 150, 0], ["FFF3E0", 72, 0.35], ["FFD9A8", 26, 0.65], ["FFD9A8", 0, 1]]
REFLECT_A   := 100, REFLECT_EXT := 0.50  ; angled edge reflection: white alpha, gone by EXT of the diagonal
GLOW_RGB    := "F5B94E", GLOW_A := 30, GLOW_W := 90   ; warm inner glow along the edge, band width in px
RIM_W       := 1.5, RIM_R := 6          ; inner white rim (px) inside the border, lit lower-left lip:
RIM_A0      := 235, RIM_A1 := 70        ; alpha at the bottom-left / top-right
WELL_PAD    := 8, WELL_R := 14          ; preview well: px around the thumbnail area, corner radius
WELL_TOP    := "EFE6D6", WELL_TOP_A := 150, WELL_BOT := "F8F2E7", WELL_BOT_A := 90   ; well fill, top -> bottom
WELL_LINE_A := 110, WELL_LIP_A := 200   ; well edge: BORDER colour top/right, white bottom/left lip
CARD_R      := 10                       ; list card corner (region ellipse size, px)
CARD_LINE   := "E6DAC6", CARD_LINE_A := 150, CARD_LIP_A := 220   ; list hairline: top/right, white bottom/left
GRAIN_AMP   := 2                        ; frosted grain, about ± levels of 255 (0 = off)
SHADOW_RGB  := "78350F", SHADOW_A := 48, SHADOW_BLUR := 20   ; warm drop shadow (alpha 0 = off)
SHADOW_DX   := 4, SHADOW_DY := -2       ; shadow offset in px, away from the light
LIST_BG     := "FDFBF7", TEXT_RGB := "181614", PROC_RGB := "6B6154", NOTE_RGB := "7A6E60"
PILL_RGB    := "D6E6F2", PILL_RIM := "BFD5E6", PILL_HI := "EEF5FA", PILL_R := 14   ; selection pill, pale blue
PILL_INSET  := 3                        ; pill gap above and below, inside its row
PANE_R      := 8 * A_ScreenDPI // 96    ; Win11 round-corner radius, scales with DPI
PANE_PAD_X  := 24, PANE_PAD_Y := 18     ; breathing room: pane margins (0 = AHK default, 20 x 12 here)
PANE_GAP    := 22, ROW_PAD := 8         ; list-to-preview gap; extra px per list row (0 = off)
INHALE_MS   := 190, INHALE_RISE := 8    ; fresh open: fade in from INHALE_A0 while rising this many px (0 ms = off)
INHALE_A0   := 48                       ; first-frame alpha: the pane shows at once, then breathes in
GLIDE_MS    := 110, GLIDE_MAX_ROWS := 3 ; selection pill glides to a row up to this far away, else snaps (0 ms = off)
ANIM_TICK   := 15                       ; animation timer period, ms
ACCENT_A    := 64, ACCENT_W := 24      ; app-colour ambient glow around the preview well: peak alpha, reach px (0 = off)
ACCENT_LIP_A := 0                      ; tinted top/right edge of the well (0 = off; a hard line reads as glare)
ACCENT_S    := 0.62, ACCENT_L := 0.80, ACCENT_MIN_S := 0.12   ; pastel saturation / lightness; greyer icons get none
ACCENT_WARM := "FFE3C2", ACCENT_WARM_MIX := 0.12  ; warm the pastel slightly; the glow's lit bottom-left corner blooms warmer
ACCENT_FILL_A := 40                    ; app-colour wash inside the well, around the thumbnail (0 = off)
ACCENT_SPILL_A := 48, ACCENT_SPILL := 0.40   ; app light spilling from the preview onto the glass: alpha, reach (share of width) (0 = off)
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
global g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x80000")   ; layered: the inhale fades it
g.BackColor := BASE_MID              ; fallback until the glass is rendered
if PANE_PAD_X                        ; before any control (reading the default here would give 11 x 7)
    g.MarginX := PANE_PAD_X
if PANE_PAD_Y
    g.MarginY := PANE_PAD_Y
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 33, "int*", 2, "uint", 4)               ; Win11 rounded corners
DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 34, "uint*", Bgr(BORDER), "uint", 4)    ; DWMWA_BORDER_COLOR
g.SetFont("s" FONT_SIZE " c" TEXT_RGB, FONT_NAME)
global lb := g.AddListBox("w" LIST_WIDTH " r10 Background" LIST_BG " 0x50 -E0x200")   ; owner-drawn (DrawItem), no edge
OnMessage(0x2B, DrawItem)            ; WM_DRAWITEM
OnMessage(0x14, EraseBg)             ; WM_ERASEBKGND: paint the cached glass
pw := Min(PREVIEW_W, A_ScreenWidth - LIST_WIDTH - 60)    ; must fit beside the list
global pv := pw > 0 ? g.AddText("x+" (PANE_GAP || 10) " yp w" pw " h" pw * 10 // 16 " BackgroundTrans") : 0   ; 16:10 thumbnail area
global thumb := 0                   ; DWM thumbnail handle of the highlighted window (0 = none)
g.AddText("xm ym Hidden", "Ag").GetPos(, , , &textH)   ; measure a line of the list font
SendMessage(0x1A0, 0, textH + ROW_PAD, lb)             ; LB_SETITEMHEIGHT: owner-draw needs it set
global paneA := 255, paneDY := 0, inhaleX := 0, inhaleY := 0, inhaleT := 0   ; inhale: pane alpha, px below its spot
global pillRow := 0, glideFrom := 0, glideTo := 0, glideT := 0   ; pill position in rows (fractional mid-glide, 0 = none)
global accents := Map(), accentRgb := "", accentKey := ""   ; process path -> pastel "RRGGBB"; shown accent
global baseDC := DllCall("CreateCompatibleDC", "ptr", 0, "ptr"), glassBase := 0   ; accent-free copy around the well
; Mood bitmaps (few / some / many windows), scaled once. Missing file = 0 = no image.
DllCall("LoadLibrary", "str", "gdiplus")
si := Buffer(24, 0), NumPut("uint", 1, si)   ; GdiplusStartupInput
global gdipToken := 0                        ; GDI+ stays up: the glass is re-rendered when the pane resizes
DllCall("gdiplus\GdiplusStartup", "ptr*", &gdipToken, "ptr", si, "ptr", 0)
global imgs := [], spans := []                 ; spans: [top, bottom] rows of each image's visible art
for mood in ["few", "some", "many"]
    imgs.Push(ScaledBitmap(A_ScriptDir "\" IMG_DIR "\" IMG_PREFIX "_" mood ".png", IMG_SIZE, &span)), spans.Push(span)
global grainBr := MakeGrain(GRAIN_AMP)       ; texture brush, kept for the script's life
; The image lives in its own per-pixel-alpha window, stacked just below the pane so the pane
; hides its lower part. Click-through and never activated (LAYERED|TRANSPARENT|NOACTIVATE).
global peek := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080020")
global peekX := 0, peekY0 := 0, peekY1 := 0, peekT := 0   ; slide-up animation state
global shade := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08080020")   ; drop shadow, below the image
global shadeBmp := 0, shadeKey := ""                       ; its HBITMAP, cached by pane size
global glassDC := DllCall("CreateCompatibleDC", "ptr", 0, "ptr"), glassBmp := 0, glassKey := ""   ; cached glass
global plate := 0, plateKey := ""                          ; its size-only layers (GDI+ bitmap)
MOOD_NOTES := ["cozy ♡", "nice ✌", "too many…"]  ; caption in the bottom-left corner, same order as imgs
g.SetFont("s" FONT_SIZE * 3 // 4 " c" NOTE_RGB)  ; smaller, muted
global moodNote := g.AddText("xm ym r1 w" LIST_WIDTH - 20 " Hidden BackgroundTrans 0x4000000")   ; list covers it on overlap
SetTimer WarmUp, -200                            ; once startup is done: render the first open's glass early

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
    Select(idx)
    UpdatePreview(wins[idx])
    if started
        SetTimer WatchAlt, 20
}

WatchAlt() {
    if DllCall("GetAsyncKeyState", "int", 0x12, "short") >= 0   ; VK_MENU: OS state, covers injected Alt
        Finish(true)
}

; One shot after startup: lay out the hidden pane for the current windows, so the glass and shadow for
; that size are cached and the first Alt+Tab only has to show them (~70 ms sooner). Nothing is shown.
WarmUp() {
    global wins
    Critical                          ; an Alt+Tab pressed now waits for it instead of interleaving
    if !cycling && (wins := CollectWindows()).Length
        ShowList(true)
}

Finish(activate) {
    global cycling
    SetTimer WatchAlt, 0
    UpdatePreview()
    SetTimer(PeekStep, 0), SetTimer(InhaleStep, 0), SetTimer(GlideStep, 0)   ; nothing runs while hidden
    peek.Hide(), shade.Hide(), g.Hide()
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
    Select(idx)
    UpdatePreview(wins[idx])
}

; Show a live DWM thumbnail of src in the preview area, tinting the well for its app; no src just drops the old one.
UpdatePreview(src := 0) {
    global thumb
    if thumb
        DllCall("dwmapi\DwmUnregisterThumbnail", "ptr", thumb), thumb := 0
    if src
        SetAccent(src)
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
    NumPut("uchar", 255, p, 36), NumPut("int", 1, p, 40)    ; DWM fades it with the pane's layered alpha
    DllCall("dwmapi\DwmUpdateThumbnailProperties", "ptr", thumb, "ptr", p)
}

; Owner-drawn list row: selection is a rounded pale-blue pill, process name muted.
; The pill sits at pillRow, so mid-glide it straddles two rows and each draws its own part.
DrawItem(wParam, lParam, *) {
    if NumGet(lParam, 24, "ptr") != lb.Hwnd         ; DRAWITEMSTRUCT.hwndItem
        return
    i := NumGet(lParam, 8, "int") + 1, dc := NumGet(lParam, 32, "ptr")
    l := NumGet(lParam, 40, "int"), t := NumGet(lParam, 44, "int")
    r := NumGet(lParam, 48, "int"), b := NumGet(lParam, 52, "int")
    rc := Buffer(16), NumPut("int", l, "int", t, "int", r, "int", b, rc)
    br := DllCall("CreateSolidBrush", "uint", Bgr(LIST_BG), "ptr")
    DllCall("FillRect", "ptr", dc, "ptr", rc, "ptr", br), DllCall("DeleteObject", "ptr", br)
    if i < 1 || i > rows.Length                     ; empty list: itemID = -1
        return true
    if pillRow && Abs(pillRow - i) < 1 {            ; the pill overlaps this row: draw it clipped to the row
        y := t + Round((pillRow - i) * (b - t))
        DllCall("SaveDC", "ptr", dc), DllCall("IntersectClipRect", "ptr", dc, "int", l, "int", t, "int", r, "int", b)
        Pill(dc, l, y, r, y + b - t), DllCall("RestoreDC", "ptr", dc, "int", -1)
    }
    DllCall("SetBkMode", "ptr", dc, "int", 1)       ; TRANSPARENT
    x := l + 14, xr := r - 14
    procW := TextWidth(dc, rows[i][2])
    titleW := Max(0, Min(TextWidth(dc, rows[i][1]), xr - x - procW))
    DrawCell(dc, rows[i][1], x, t, x + titleW, b, Bgr(TEXT_RGB))
    DrawCell(dc, rows[i][2], x + titleW, t, xr, b, Bgr(PROC_RGB))
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

ShowList(warm := false) {   ; warm: stop once the glass and shadow are rendered (WarmUp)
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
    lb.GetPos(, , &lw, &lh)                  ; round the card; the system owns (and frees) the region
    DllCall("SetWindowRgn", "ptr", lb.Hwnd, "ptr", DllCall("CreateRoundRectRgn", "int", 0, "int", 0
        , "int", lw + 1, "int", lh + 1, "int", CARD_R, "int", CARD_R, "ptr"), "int", true)
    moodNote.Visible := false        ; hidden controls don't count for AutoSize
    wasShown := DllCall("IsWindowVisible", "ptr", g.Hwnd)
    SetTimer GlideStep, 0
    global pillRow := wasShown ? idx : 0   ; fresh rows: the first Select snaps; re-show: pill stays put, no blank frame
    g.Show("Hide AutoSize")
    g.GetClientPos(, , &cw, &ch)
    n := wins.Length, k := MoodOf(n)  ; few / some / many
    moodNote.Text := n " window" (n = 1 ? "" : "s") " · " MOOD_NOTES[k]
    moodNote.GetPos(, , , &nh)
    moodNote.Move(, ch - g.MarginY - nh), moodNote.Visible := true
    GlassRender(cw, ch, lh)
    g.GetPos(, , &w, &h)
    if warm
        return ShadowBitmap(w, h)
    mi := Buffer(40, 0), NumPut("uint", 40, mi)
    DllCall("GetMonitorInfoW", "ptr", CurrentMonitor(), "ptr", mi)
    l := NumGet(mi, 20, "int"), t := NumGet(mi, 24, "int")   ; rcWork
    r := NumGet(mi, 28, "int"), b := NumGet(mi, 32, "int")
    InhaleStart(!wasShown, x := l + (r - l - w) // 2, y := t + (b - t - h) // 2)   ; sets alpha before the Show
    g.Show("NA x" x " y" (y + paneDY))
    DllCall("RedrawWindow", "ptr", g.Hwnd, "ptr", 0, "ptr", 0, "uint", 0x185)   ; INVALIDATE|ERASE|ALLCHILDREN|UPDATENOW
    ShowShadow(w, h)                 ; before the image, so the stack ends up pane > image > shadow
    ShowPeek(imgs[k], PeekShare(n), !wasShown, spans[k])
}

; Share of the art above the pane for n windows: PEEK_MIN at 1, evenly up to PEEK_MAX at MANY_FROM + 4 and beyond.
PeekShare(n) => PEEK_MIN + (PEEK_MAX - PEEK_MIN) * Min(Max(n - 1, 0) / (MANY_FROM + 3), 1)

; Put the image window behind the pane's top-left edge, `share` of its art showing (transparent padding
; ignored). It slides up from fully hidden once the pane has breathed in (it would show through the faint
; pane), or glides from where it is when the count changes.
ShowPeek(hbm, share, fromHidden, span := [0, IMG_SIZE]) {
    global peekX, peekY0, peekY1
    if !hbm
        return peek.Hide()
    g.GetPos(&x, &y)
    peekX := x + (PANE_PAD_X || 20)
    peekY1 := y - paneDY - Round(span[1] + (span[2] - span[1]) * share)   ; paneDY: the pane is still rising
    if fromHidden || !DllCall("IsWindowVisible", "ptr", peek.Hwnd)
        peekY0 := y
    else
        WinGetPos(, &peekY0, , , peek.Hwnd)
    Layer(peek, hbm, peekX, peekY0, IMG_SIZE, IMG_SIZE, paneA = 255 ? 255 : 0)   ; inhaling: InhaleStep starts it
    DllCall("SetWindowPos", "ptr", peek.Hwnd, "ptr", g.Hwnd, "int", 0, "int", 0, "int", 0, "int", 0
        , "uint", 0x53)                                             ; just below the pane: NOSIZE|NOMOVE|NOACTIVATE|SHOWWINDOW
    if paneA = 255
        PeekStart()
}

PeekStart() {
    global peekT := A_TickCount
    SetTimer PeekStep, ANIM_TICK
}

PeekStep() {
    p := Min((A_TickCount - peekT) / 180, 1), e := 1 - (1 - p) ** 3   ; 180 ms, ease-out
    DllCall("SetWindowPos", "ptr", peek.Hwnd, "ptr", 0, "int", peekX, "int", Round(peekY0 + (peekY1 - peekY0) * e)
        , "int", 0, "int", 0, "uint", 0x15)                         ; NOSIZE|NOZORDER|NOACTIVATE
    if p >= 1
        SetTimer PeekStep, 0
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

; Glass rendering, animation and accent helpers (functions only); the Settings… panel and settings.ini.
#Include %A_LineFile%\..\alttab-glass.ahk
#Include %A_LineFile%\..\settings-panel.ahk
