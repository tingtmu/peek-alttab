; Settings… panel for peek-alttab.ahk and elegant-alttab.ahk (#Included by both; tray menu > Settings…, or
; the desktop icon, desktop-icon.ahk, which starts the script with /settings):
; mood images and their window ranges, how far the image peeks (peek only), the list font. Built when
; opened and destroyed when closed, so nothing of it exists, runs or listens while closed, and Alt+Tab
; never waits on it. Values go to settings.ini (settings-store.ahk); Save reloads the script to apply them.

#Include %A_LineFile%\..\gdip-helpers.ahk
#Include %A_LineFile%\..\settings-store.ahk
#Include %A_LineFile%\..\settings-paint.ahk
#Include %A_LineFile%\..\cutout.ahk
#Include %A_LineFile%\..\desktop-icon.ahk

; The switcher's palette (same values as the glass constants in peek-alttab.ahk), one restrained accent.
global LOOK := {bgTop: "FCF9F4", bg: "FAF6EF", bgBot: "F5EEE2", card: "FDFBF7", line: "E6DAC6", border: "D9CBB4"
    , text: "181614", muted: "6B6154", soft: "8C8174", faint: "D8CEBF", pill: "D6E6F2", pillRim: "BFD5E6"
    , pillHi: "EEF5FA", accent: "6F93B6", shadow: "78350F", wellTop: "EFE6D6", wellBot: "F8F2E7", face: "Segoe UI"}
global pnl := 0                                       ; the open panel's state; 0 = closed
A_TrayMenu.Insert("1&", "Settings…", SettingsOpen)
A_TrayMenu.Insert("2&", "Desktop icon", DesktopIconToggle)
A_TrayMenu.Insert("3&")
A_TrayMenu.Default := "Settings…"                     ; double-click the tray icon
if A_IsCompiled                                       ; an exe's menu is just Suspend, Pause, Exit: add Reload before Exit
    A_TrayMenu.Insert(DllCall("GetMenuItemCount", "ptr", A_TrayMenu.Handle) "&", "&Reload Script", (*) => Reload())
else if FileExist(AppDir() "assets\peek-alttab.ico")  ; the exe carries the icon itself
    TraySetIcon AppDir() "assets\peek-alttab.ico"
DesktopIconStart()                                    ; check mark, "/settings", the exe's first-run question

Dpx(v) => Round(v * pnl.scale)                        ; panel layout units -> pixels, fitted to the work area

SettingsOpen(*) {
    global pnl
    if pnl
        return WinActivate(pnl.gui)
    DllCall("LoadLibrary", "str", "gdiplus"), si := Buffer(24, 0), NumPut("uint", 1, si)
    DllCall("gdiplus\GdiplusStartup", "ptr*", &tok := 0, "ptr", si, "ptr", 0)   ; own token: elegant shuts its own down
    PendingClear()                                    ; leftovers of a crash
    peek := SettingsHas("PEEK_MIN")
    pnl := {tok: tok, el: Map(), cards: [], frames: [], labels: [], hover: 0, side: 0, drag: 0, dirty: false
        , note: PanelIssues(), scale: A_ScreenDPI / 96, work: PanelWorkArea()
        , some: SOME_FROM, many: MANY_FROM, face: FONT_NAME, size: FONT_SIZE
        , peek: peek ? [Round(SettingsGet("PEEK_MIN") * 100), Round(SettingsGet("PEEK_MAX") * 100)] : 0}
    g := PanelBuild(&w, &h)
    for i in [1, 2, 3]
        PanelLoadCard(i)
    PanelSurface(w, h)
    PanelHook(true)
    g.OnEvent("Close", PanelClose), g.OnEvent("Escape", PanelClose), g.OnEvent("DropFiles", PanelDrop)
    for a, v in Map(33, 2, 34, Bgr(LOOK.border), 35, Bgr(LOOK.bgTop), 36, Bgr(LOOK.text))   ; round corners, border,
        DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", a, "uint*", v, "uint", 4)   ; ivory caption, title
    PanelShow(w, h)
    PanelFontList()
}

PanelWorkArea() {   ; capture the target monitor before creating the hidden panel
    mi := Buffer(40, 0), NumPut("uint", 40, mi)
    if !DllCall("GetMonitorInfoW", "ptr", CurrentMonitor(), "ptr", mi)
        throw OSError()
    l := NumGet(mi, 20, "int"), t := NumGet(mi, 24, "int")
    return {l: l, t: t, w: NumGet(mi, 28, "int") - l, h: NumGet(mi, 32, "int") - t}
}

PanelBuild(&w, &h) {   ; measure the full window, then rebuild smaller only when it cannot fit
    loop {
        pnl.gui := g := Gui("-MinimizeBox -MaximizeBox -DPIScale", "peek-alttab settings")
        g.BackColor := LOOK.bg, g.MarginX := 0, g.MarginY := 0
        g.SetFont("s" (10 * pnl.scale * 96 / A_ScreenDPI) " c" LOOK.text, LOOK.face)
        PanelFonts()
        h := PanelLayout(w := Dpx(624))
        g.Show("Hide w" w " h" h), g.GetPos(, , &ww, &wh), g.GetClientPos(, , &cw, &ch)
        margin := Dpx(12), area := pnl.work
        fit := Min(1, (area.w - (ww - cw) - 2 * margin) / w, (area.h - (wh - ch) - 2 * margin) / h)
        if fit >= 1
            return g
        g.Destroy()
        for k, f in pnl.f
            DllCall("DeleteObject", "ptr", f)
        pnl.scale *= fit * 0.995                      ; leave room for font/control rounding
        pnl.el := Map(), pnl.cards := [], pnl.frames := [], pnl.labels := []
    }
}

; Cards (few / some / many) with their range steppers, the peek scenes and sliders, the font row, the buttons.
; Tab order follows creation. Returns the client height.
PanelLayout(w) {
    pad := Dpx(28), gap := Dpx(16), cw := (w - 2 * pad - 2 * gap) // 3, y := Dpx(20)
    pnl.labels.Push(["MOOD IMAGES", pad, y]), y += Dpx(26)
    for i, mood in Moods() {   ; few starts at 1; some and many get a "starts at" stepper
        x := pad + (i - 1) * (cw + gap), c := {mood: mood, thumb: 0, big: 0, span: [0, 1], busy: false, pending: false}
        pnl.frames.Push([x, y, cw, Dpx(232)])
        c.card := PanelAdd("card", x + Dpx(8), y + Dpx(8), cw - Dpx(16), Dpx(182), PaintCard.Bind(i)
            , "Click to choose the picture for “" MOOD_NOTES[i] "”, or drop one here.", PanelPick.Bind(i))
        if i > 1
            PanelAdd("step", x + Dpx(12), y + Dpx(194), Dpx(80), Dpx(28), PaintStepper.Bind(i)
                , "Where “" MOOD_NOTES[i] "” starts: the fewest windows that count.", PanelStepClick.Bind(i)).i := i
        c.clean := PanelAdd("chip", x + cw - Dpx(74), y + Dpx(194), Dpx(62), Dpx(28), PaintChip.Bind(i)
            , "Clean background: remove a plain light background and crop.", PanelClean.Bind(i))
        c.clean.ctl.Visible := false
        pnl.cards.Push(c)
    }
    y += Dpx(232) + Dpx(8)
    pnl.hint := PanelAdd("hint", pad + Dpx(2), y, w - 2 * pad, Dpx(20), PaintHint), y += Dpx(20) + Dpx(18)
    if pnl.peek
        y := PanelLayoutPeek(w, pad, gap, y)
    pnl.labels.Push(["LIST FONT", pad, y]), y += Dpx(26)
    pnl.ddl := pnl.gui.AddDropDownList("x" pad " y" y " w" Dpx(330) " r16")
    pnl.ddl.OnEvent("Change", PanelFontPick), pnl.ddl.GetPos(, , , &dh)
    PanelAdd("step", w - pad - Dpx(108), y + (dh - Dpx(28)) // 2, Dpx(108), Dpx(28), PaintStepper.Bind(4)
        , "Text size of the list, in points (10–24).", PanelStepClick.Bind(4)).i := 4
    y += dh + Dpx(12)
    pnl.sample := PanelAdd("sample", pad, y, w - 2 * pad, Dpx(58), PaintSample), y += Dpx(58) + Dpx(26)
    PanelAdd("button", pad - Dpx(12), y, Dpx(150), Dpx(34), PaintButton.Bind("Reset to defaults", 0)
        , "Put the panel's settings back to the built-in ones (asks first).", PanelReset)
    PanelAdd("button", w - pad - Dpx(212), y, Dpx(100), Dpx(34), PaintButton.Bind("Cancel", 1), "Close without saving (Esc).", PanelClose)
    PanelAdd("button", w - pad - Dpx(100), y, Dpx(100), Dpx(34), PaintButton.Bind("Save", 2), "Save and apply (Enter).", PanelSave)
    return y + Dpx(34) + Dpx(22)
}

PanelLayoutPeek(w, pad, gap, y) {   ; two scenes (1 window, many windows), a slider under each
    pnl.labels.Push(["PEEK HEIGHT", pad, y]), y += Dpx(26), sw := (w - 2 * pad - gap) // 2
    for j in [1, 2] {
        x := pad + (j - 1) * (sw + gap)
        PanelAdd("scene", x, y, sw, Dpx(120), PaintScene.Bind(j))
        PanelAdd("slider", x, y + Dpx(122), sw, Dpx(28), PaintSlider.Bind(j), j = 1
            ? "How much of the picture shows above the pane with a single window."
            : "How much shows once the window count reaches many (and beyond).").j := j
    }
    return y + Dpx(150) + Dpx(20)
}

; An owner-drawn element: a focusable button, or a plain owner-drawn static for the display-only kinds.
PanelAdd(kind, x, y, w, h, paint, hint := "", click := 0) {
    if kind ~= "^(hint|scene|sample)$"
        c := pnl.gui.AddText("x" x " y" y " w" w " h" h " 0xD")            ; SS_OWNERDRAW
    else {
        c := pnl.gui.AddButton("x" x " y" y " w" w " h" h)
        DllCall("SetWindowLongPtr", "ptr", c.Hwnd, "int", -16, "ptr", ControlGetStyle(c) & ~0xF | 0xB)   ; BS_OWNERDRAW (Add masks it)
    }
    if click
        c.OnEvent("Click", click), c.OnEvent("DoubleClick", click)   ; quick repeat clicks come as double-clicks
    return pnl.el[c.Hwnd] := {ctl: c, kind: kind, x: x, y: y, w: w, h: h, paint: paint, hint: hint}
}

PanelIssues() {   ; what settings.ini had wrong at startup, for the hint line ("" = nothing)
    n := SETTINGS_ISSUES.Length
    return n ? "settings.ini: " SETTINGS_ISSUES[1] (n > 1 ? "  (+" n - 1 " more)" : "") : ""
}

PanelShow(w, h) {   ; centred on the active window's monitor (or the cursor's)
    g := pnl.gui, area := pnl.work
    g.Show("Hide w" w " h" h), g.GetPos(, , &ww, &wh)
    g.Show("x" (area.l + (area.w - ww) // 2) " y" (area.t + (area.h - wh) // 2))
}

PanelFontList() {
    names := FontFamilies(), at := 0
    for i, n in names
        if n = pnl.face
            at := i
    if !at                                            ; e.g. a font known by another name: keep it on top
        names.InsertAt(1, pnl.face), at := 1
    pnl.ddl.Add(names), pnl.ddl.Choose(at)
}

PanelHook(on) {   ; message handlers exist only while the panel is open
    static msgs := Map(0x2B, PanelDrawItem, 0x14, PanelErase, 0x100, PanelKey, 0x200, PanelMouse, 0x201, PanelMouse
        , 0x202, PanelMouse, 0x2A3, PanelLeave, 0x20, PanelCursor)   ; DRAWITEM ERASEBKGND KEYDOWN mouse MOUSELEAVE SETCURSOR
    for m, f in msgs
        OnMessage(m, f, on ? 1 : 0)
}

PanelClose(*) {
    global pnl
    if !pnl
        return
    CutoutCancel(), PanelHook(false), pnl.gui.Destroy(), PendingClear()
    for c in pnl.cards
        for b in [c.thumb, c.big]
            if b
                DllCall("gdiplus\GdipDisposeImage", "ptr", b)
    for k, f in pnl.f
        DllCall("DeleteObject", "ptr", f)
    DllCall("SelectObject", "ptr", pnl.surfDC, "ptr", pnl.surfOld), DllCall("DeleteObject", "ptr", pnl.surfBmp)
    DllCall("DeleteDC", "ptr", pnl.surfDC), DllCall("gdiplus\GdiplusShutdown", "ptr", pnl.tok)
    pnl := 0
}

; ----- Messages: painting, keys, mouse -----

PanelDrawItem(wParam, lParam, msg, hwnd) {   ; WM_DRAWITEM: surface underneath, then the element's painter
    if !pnl || hwnd != pnl.gui.Hwnd || !(e := pnl.el.Get(NumGet(lParam, 24, "ptr"), 0))
        return
    dc := NumGet(lParam, 32, "ptr"), st := NumGet(lParam, 16, "uint") | (pnl.hover = e.ctl.Hwnd ? 0x10000 : 0)
    mdc := DllCall("CreateCompatibleDC", "ptr", dc, "ptr"), bmp := DllCall("CreateCompatibleBitmap", "ptr", dc, "int", e.w, "int", e.h, "ptr")
    ob := DllCall("SelectObject", "ptr", mdc, "ptr", bmp, "ptr")
    DllCall("BitBlt", "ptr", mdc, "int", 0, "int", 0, "int", e.w, "int", e.h, "ptr", pnl.surfDC, "int", e.x, "int", e.y, "uint", 0xCC0020)
    paint := e.paint, paint(mdc, e.w, e.h, st)       ; st: ODS_* bits, 0x10000 = hovered
    DllCall("BitBlt", "ptr", dc, "int", 0, "int", 0, "int", e.w, "int", e.h, "ptr", mdc, "int", 0, "int", 0, "uint", 0xCC0020)
    DllCall("SelectObject", "ptr", mdc, "ptr", ob), DllCall("DeleteObject", "ptr", bmp), DllCall("DeleteDC", "ptr", mdc)
    return true
}

PanelErase(wParam, lParam, msg, hwnd) {   ; WM_ERASEBKGND: the cached surface
    if !pnl || hwnd != pnl.gui.Hwnd
        return
    pnl.gui.GetClientPos(, , &w, &h)
    DllCall("BitBlt", "ptr", wParam, "int", 0, "int", 0, "int", w, "int", h, "ptr", pnl.surfDC, "int", 0, "int", 0, "uint", 0xCC0020)
    return 1
}

PanelKey(wParam, lParam, msg, hwnd) {   ; Enter = Save; arrows / + / - / PgUp / PgDn on steppers and sliders
    static steps := Map(37, -1, 40, -1, 39, 1, 38, 1, 0xBB, 1, 0x6B, 1, 0xBD, -1, 0x6D, -1, 33, 10, 34, -10, 36, -100, 35, 100)
    if !pnl || DllCall("GetAncestor", "ptr", hwnd, "uint", 2, "ptr") != pnl.gui.Hwnd   ; GA_ROOT
        return
    if wParam = 13 {
        if SendMessage(0x157, 0, 0, pnl.ddl)          ; CB_GETDROPPEDSTATE: Enter picks from the open list
            return
        return (PanelSave(), 0)
    }
    if !(e := pnl.el.Get(hwnd, 0)) || !steps.Has(wParam) || !(e.kind = "step" || e.kind = "slider")
        return
    if e.kind = "step"
        PanelStep(e.i, steps[wParam] > 0 ? 1 : -1)
    else
        PanelPeek(e.j, pnl.peek[e.j] + steps[wParam])
    return 0
}

PanelMouse(wParam, lParam, msg, hwnd) {   ; slider drags, hover (WM_MOUSEMOVE / LBUTTONDOWN / LBUTTONUP)
    if !pnl
        return
    x := lParam << 48 >> 48, e := pnl.el.Get(hwnd, 0)  ; signed client x
    if msg = 0x201 && e && e.kind = "slider" {
        pnl.drag := hwnd, DllCall("SetCapture", "ptr", hwnd), e.ctl.Focus()
        return (PanelSlideTo(e, x), 0)
    }
    if pnl.drag && pnl.drag = hwnd {
        if msg = 0x200 && wParam & 1                  ; MK_LBUTTON
            PanelSlideTo(e, x)
        else
            pnl.drag := 0, DllCall("ReleaseCapture")
        return 0
    }
    if msg = 0x200
        PanelHover(hwnd, e, x)
}

PanelHover(hwnd, e, x) {   ; track the element under the mouse (and a stepper's - / + side) for hover looks and hints
    side := e && e.kind = "step" ? (x < e.w / 3 ? -1 : x > e.w * 2 / 3 ? 1 : 0) : 0
    h := e && e.hint != "" ? hwnd : 0
    if h = pnl.hover && side = pnl.side
        return
    old := pnl.hover, pnl.hover := h, pnl.side := side
    PanelInvalidate(old), PanelInvalidate(h), PanelInvalidate(pnl.hint.ctl.Hwnd)
    if h
        tme := Buffer(24, 0), NumPut("uint", 24, "uint", 2, "ptr", h, tme), DllCall("TrackMouseEvent", "ptr", tme)   ; TME_LEAVE
}

PanelLeave(wParam, lParam, msg, hwnd) {   ; WM_MOUSELEAVE
    if pnl && hwnd = pnl.hover
        pnl.hover := 0, PanelInvalidate(hwnd), PanelInvalidate(pnl.hint.ctl.Hwnd)
}

PanelCursor(wParam, lParam, msg, hwnd) {   ; WM_SETCURSOR: a hand over anything clickable
    if pnl && (e := pnl.el.Get(wParam, 0)) && e.hint != "" && e.kind != "slider"
        return (DllCall("SetCursor", "ptr", DllCall("LoadCursor", "ptr", 0, "ptr", 32649, "ptr")), 1)   ; IDC_HAND
}

PanelInvalidate(hwnd) => hwnd && DllCall("InvalidateRect", "ptr", hwnd, "ptr", 0, "int", 0)

PanelRedraw(kinds*) {   ; repaint every element of these kinds
    for hwnd, e in pnl.el
        for k in kinds
            if e.kind = k
                PanelInvalidate(hwnd)
}

PanelNote(text) {   ; a message in the hint line (hover hints still take its place for a moment)
    pnl.note := text, PanelInvalidate(pnl.hint.ctl.Hwnd)
}

; ----- Actions -----

PanelStepClick(i, ctl, *) {   ; the - or + third of a stepper; Space (cursor elsewhere) is left to the arrows
    pt := Buffer(8), DllCall("GetCursorPos", "ptr", pt), DllCall("ScreenToClient", "ptr", ctl.Hwnd, "ptr", pt)
    e := pnl.el[ctl.Hwnd], x := NumGet(pt, 0, "int"), y := NumGet(pt, 4, "int")
    if x >= 0 && y >= 0 && x < e.w && y < e.h && (x < e.w / 3 || x > e.w * 2 / 3)
        PanelStep(i, x < e.w / 3 ? -1 : 1)
}

PanelStep(i, d) {   ; 2 = some starts at, 3 = many starts at, 4 = font size; each kept within its neighbours
    switch i {
    case 2: v := pnl.some, pnl.some := Min(Max(v + d, 2), pnl.many - 1), changed := pnl.some != v
    case 3: v := pnl.many, pnl.many := Min(Max(v + d, pnl.some + 1), 30), changed := pnl.many != v
    case 4: v := pnl.size, pnl.size := Min(Max(v + d, 10), 24), changed := pnl.size != v
    default: return
    }
    if !changed
        return
    pnl.dirty := true
    if i = 4
        PanelSampleFont(), PanelRedraw("step", "sample")
    else
        PanelRedraw("step", "card", "scene")
}

PanelPeek(j, v) {   ; slider j (1 = min, 2 = max) to v %; the other one makes room so min < max
    p := [pnl.peek[1], pnl.peek[2]], p[j] := v := Min(Max(v, 30), 100)
    if p[1] >= p[2] && j = 1
        p[2] := Min(v + 1, 100), p[1] := p[2] - 1
    else if p[1] >= p[2]
        p[1] := Max(v - 1, 30), p[2] := p[1] + 1
    if p[1] = pnl.peek[1] && p[2] = pnl.peek[2]
        return
    pnl.peek := p, pnl.dirty := true, PanelRedraw("slider", "scene")
}

PanelSlideTo(e, x) {
    r := Dpx(9)
    PanelPeek(e.j, 30 + Round((x - r) / Max(e.w - 2 * r, 1) * 70))
}

PanelFontPick(ctl, *) {
    pnl.face := ctl.Text, pnl.dirty := true, PanelSampleFont(), PanelRedraw("sample")
}

PanelPick(i, *) {   ; card click: file picker
    pnl.gui.Opt("+OwnDialogs")
    if pnl.cards[i].busy
        return
    f := FileSelect(1, , "Choose the picture for “" MOOD_NOTES[i] "”", "Pictures (*.png; *.jpg; *.jpeg; *.bmp; *.gif)")
    if f != "" && pnl
        PanelImport(i, f)
}

PanelDrop(gui, ctl, files, x, y) {   ; a file dropped on the window: the card under the drop point takes it
    for i, f in pnl.frames
        if x >= f[1] && x < f[1] + f[3] && y >= f[2] && y < f[2] + f[4]
            return pnl.cards[i].busy ? 0 : PanelImport(i, files[1])
    PanelNote("Drop the picture onto one of the three cards.")
}

PanelImport(i, file) {   ; the picture becomes this card's pending one (images\custom_<mood>.pending.png)
    if why := ImportImage(file, PendingImage(Moods()[i]))
        return PanelNote("That file didn't work: " why ".")
    pnl.dirty := true, PanelLoadCard(i)
    PanelNote("New picture for “" MOOD_NOTES[i] "”. Save to use it, or clean its background first.")
}

; (Re)load card i's picture: the pending one, else the current set's. Peek also keeps it at IMG_SIZE with
; its art span (ArtSpan, as the switcher measures it) for the peek scenes.
PanelLoadCard(i) {
    c := pnl.cards[i], old := [c.thumb, c.big]
    pending := FileExist(PendingImage(c.mood)) != ""
    file := pending ? PendingImage(c.mood) : MoodImage(IMG_PREFIX, c.mood)
    thumb := FitBitmap(file, Dpx(112)), big := pnl.peek ? FitBitmap(file, IMG_SIZE) : 0
    span := big ? ArtSpan(big, IMG_SIZE) : [0, 1]
    Critical                                          ; a paint may interrupt between lines: swap, then free
    c.pending := pending, c.file := file, c.thumb := thumb, c.big := big, c.span := span
    Critical "Off"
    for b in old
        if b
            DllCall("gdiplus\GdipDisposeImage", "ptr", b)
    PanelChips(), PanelRedraw("card", "scene", "hint")
}

PanelChips() {   ; "Clean" shows on cards with the user's own picture
    for c in pnl.cards
        c.clean.ctl.Visible := c.thumb && (c.pending || IMG_PREFIX = "custom")
}

PanelClean(i, *) {   ; cutout.ahk on the card's working copy (made from the live picture if needed), async
    c := pnl.cards[i], pend := PendingImage(c.mood)
    if c.busy
        return
    made := !c.pending
    if made
        try FileCopy c.file, pend, 1
        catch as e
            return PanelNote("Couldn't prepare the picture (" e.Message ").")
    c.busy := true, c.clean.ctl.Enabled := false, PanelRedraw("card", "chip")
    PanelNote("Cleaning “" MOOD_NOTES[i] "”…")
    CutoutRun(pend, PanelCleaned.Bind(i, made))
}

PanelCleaned(i, made, r) {
    if !pnl
        return
    c := pnl.cards[i], c.busy := false, c.clean.ctl.Enabled := true
    if made && !r.changed                             ; nothing to keep: drop the copy again
        try FileDelete PendingImage(c.mood)
    pnl.dirty := pnl.dirty || r.changed
    PanelLoadCard(i), PanelNote("“" MOOD_NOTES[i] "”: " r.msg ".")
}

PanelSave(*) {   ; write settings.ini (+ pictures) and reload; nothing changed = just close
    if !pnl
        return
    for c in pnl.cards
        if c.busy
            return PanelNote("Still cleaning a picture, one moment…")
    if !pnl.dirty
        return PanelClose()
    vals := Map("FONT_NAME", pnl.face, "FONT_SIZE", pnl.size, "SOME_FROM", pnl.some, "MANY_FROM", pnl.many, "IMG_PREFIX", IMG_PREFIX)
    if pnl.peek
        vals["PEEK_MIN"] := pnl.peek[1] / 100, vals["PEEK_MAX"] := pnl.peek[2] / 100
    for c in pnl.cards
        if c.pending {
            if err := ImagesCommit(IMG_PREFIX)
                return PanelFail(err)
            vals["IMG_PREFIX"] := "custom"
            break
        }
    if err := SettingsWrite(vals)
        return PanelFail(err)
    Reload()
}

PanelReset(*) {
    pnl.gui.Opt("+OwnDialogs")
    if MsgBox("Put the panel's settings back to the built-in defaults?`n`nYour pictures stay in the images folder, "
        . "and lines you added to settings.ini yourself (such as WM_PROCESS) are kept.", "peek-alttab settings", "OKCancel Iconi Default2") != "OK"
        return
    if err := SettingsReset()
        return PanelFail(err)
    PendingClear(), Reload()
}

PanelFail(err) {
    pnl.gui.Opt("+OwnDialogs")
    MsgBox "The settings couldn't be saved:`n" err, "peek-alttab settings", "Icon!"
}
