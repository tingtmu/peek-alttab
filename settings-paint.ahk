; Drawing for the Settings… panel (#Included by settings-panel.ahk; functions only). Light comes from the
; bottom-left like the switcher's glass: lit edges are white, shadows fall up and to the right. Shapes are
; GDI+ (antialiased); text is GDI DrawText, which falls back to CJK / symbol fonts by itself.

; ----- Fonts and text -----

PanelMakeFont(pt, weight := 400, face := "") => DllCall("CreateFontW", "int", -Dpx(pt * 96 / 72), "int", 0
    , "int", 0, "int", 0, "int", weight, "uint", 0, "uint", 0, "uint", 0, "uint", 1, "uint", 0, "uint", 0
    , "uint", 5, "uint", 0, "str", face = "" ? LOOK.face : face, "ptr")   ; DEFAULT_CHARSET, CLEARTYPE_QUALITY

PanelFonts() {   ; label: section titles; cap: card captions; num: stepper values
    pnl.f := Map("label", PanelMakeFont(7.5, 600), "body", PanelMakeFont(10), "cap", PanelMakeFont(10.5, 600)
        , "small", PanelMakeFont(9), "num", PanelMakeFont(10, 600))
    PanelSampleFont()
}

PanelSampleFont() {   ; the list font as chosen, for the sample row (swapped in before the old one is freed)
    old := pnl.f.Get("sample", 0), pnl.f["sample"] := PanelMakeFont(pnl.size, 400, pnl.face)
    if old
        DllCall("DeleteObject", "ptr", old)
}

; s in rect x, y, w, h; fmt: DrawText flags (default single line, vertically centred; | 1 centre, | 2 right).
PanelText(dc, s, x, y, w, h, font, rgb, fmt := 0x24) {
    of := DllCall("SelectObject", "ptr", dc, "ptr", font, "ptr")
    DllCall("SetBkMode", "ptr", dc, "int", 1), DllCall("SetTextColor", "ptr", dc, "uint", Bgr(rgb))
    rc := Buffer(16), NumPut("int", Round(x), "int", Round(y), "int", Round(x + w), "int", Round(y + h), rc)
    DllCall("DrawTextW", "ptr", dc, "wstr", s, "int", -1, "ptr", rc, "uint", fmt | 0x8800)   ; NOPREFIX|END_ELLIPSIS
    DllCall("SelectObject", "ptr", dc, "ptr", of)
}

; ----- Shapes -----

FillRound(gr, x, y, w, h, r, argb) {
    path := RoundPath(x, y, w, h, Min(r, h / 2, w / 2))
    DllCall("gdiplus\GdipCreateSolidFill", "uint", argb, "ptr*", &br := 0)
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br), DllCall("gdiplus\GdipDeletePath", "ptr", path)
}

Ring(gr, x, y, w, h, r, rgb, a, width := 1) => Stroke(gr, x, y, w, h, Min(r, h / 2), width, [[rgb, a, 0], [rgb, a, 1]])

Disc(gr, cx, cy, r, fill, line := 0) {   ; circle; fill / line are ARGB (0 = none)
    if fill {
        DllCall("gdiplus\GdipCreateSolidFill", "uint", fill, "ptr*", &br := 0)
        DllCall("gdiplus\GdipFillEllipse", "ptr", gr, "ptr", br, "float", cx - r, "float", cy - r, "float", 2 * r, "float", 2 * r)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    }
    if line {
        DllCall("gdiplus\GdipCreatePen1", "uint", line, "float", 1, "int", 2, "ptr*", &pen := 0)   ; UnitPixel
        DllCall("gdiplus\GdipDrawEllipse", "ptr", gr, "ptr", pen, "float", cx - r + 0.5, "float", cy - r + 0.5, "float", 2 * r - 1, "float", 2 * r - 1)
        DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    }
}

FocusRing(gr, w, h, r, st) {   ; keyboard focus (cues shown): a soft accent ring just inside the element
    if (st & 0x10) && !(st & 0x200)                   ; ODS_FOCUS without ODS_NOFOCUSRECT
        Ring(gr, 1, 1, w - 2, h - 2, r, LOOK.accent, 200, 2)
}

; ----- The surface: background, card frames, section labels (rendered once per open) -----

PanelSurface(w, h) {
    bm := NewBitmap(w, h), gr := Canvas(bm)
    Fill(gr, FadeBrush(0, 0, w, h, 90, [[LOOK.bgTop, 255, 0], [LOOK.bg, 255, 0.45], [LOOK.bgBot, 255, 1]]), w, h)
    RadialFill(gr, 0, h, 0.65 * w, 0.5 * h, [["FFFFFF", 110, 0], ["FFF7EA", 45, 0.5], ["FFF7EA", 0, 1]])   ; light, bottom-left
    for f in pnl.frames
        PaintFrame(gr, f*)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    pnl.surfDC := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    pnl.surfOld := DllCall("SelectObject", "ptr", pnl.surfDC, "ptr", pnl.surfBmp := ToHbm(bm), "ptr")
    DllCall("SetTextCharacterExtra", "ptr", pnl.surfDC, "int", Dpx(1))   ; airy small caps
    for l in pnl.labels
        PanelText(pnl.surfDC, l[1], l[2], l[3], Dpx(300), Dpx(16), pnl.f["label"], LOOK.soft)
    DllCall("SetTextCharacterExtra", "ptr", pnl.surfDC, "int", 0)
}

PaintFrame(gr, x, y, w, h) {   ; a card: soft warm shadow up-right, lit-corner fill, hairline with a white lower-left lip
    r := Dpx(14), b := Dpx(14), sw := w + 2 * b, sh := h + 2 * b
    path := RoundPath(x - b + Dpx(3), y - b - Dpx(2), sw, sh, r + b)
    EdgeFade(gr, path, LOOK.shadow, 0, 20, (w - 2 * b) / sw, (h - 2 * b) / sh, true)
    DllCall("gdiplus\GdipDeletePath", "ptr", path)
    path := RoundPath(x, y, w, h, r), br := FadeBrush(x, y, w, h, 315, [["FFFFFF", 255, 0], [LOOK.card, 255, 0.55], [LOOK.card, 255, 1]])
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br), DllCall("gdiplus\GdipDeletePath", "ptr", path)
    Stroke(gr, x + 0.5, y + 0.5, w - 1, h - 1, r, 1, Lip(230, LOOK.line, 170))
}

; ----- Element painters: (dc, w, h, st); dc already holds the surface beneath. st: ODS_* | 0x10000 hovered -----

PaintCard(i, dc, w, h, st) {   ; picture well, caption, window range
    c := pnl.cards[i], wh := Dpx(134), r := Dpx(12), hov := st & 0x10000, t := Dpx(112)
    gr := Canvas(0, dc), path := RoundPath(0.5, 0.5, w - 1, wh - 1, r)
    br := FadeBrush(0, 0, w, wh, 90, hov ? [[LOOK.pillHi, 255, 0], [LOOK.pill, 150, 1]] : [[LOOK.wellTop, 140, 0], [LOOK.wellBot, 80, 1]])
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", path)
    DllCall("gdiplus\GdipDeleteBrush", "ptr", br), DllCall("gdiplus\GdipDeletePath", "ptr", path)
    Stroke(gr, 0.5, 0.5, w - 1, wh - 1, r, 1, Lip(210, hov ? LOOK.pillRim : LOOK.border, hov ? 230 : 120))
    FocusRing(gr, w, wh, r, st)
    if c.thumb {
        DllCall("gdiplus\GdipSetInterpolationMode", "ptr", gr, "int", 7)
        DllCall("gdiplus\GdipDrawImageRectI", "ptr", gr, "ptr", c.thumb, "int", (w - t) // 2, "int", (wh - t) // 2, "int", t, "int", t)
    }
    if c.busy                                         ; veil while the cleaning runs
        FillRound(gr, 1, 1, w - 2, wh - 2, r, Argb("FFFFFF", 165))
    if c.pending                                      ; a new, unsaved picture
        Disc(gr, Dpx(13), Dpx(13), Dpx(3.5), Argb(LOOK.accent, 255))
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    if c.busy || !c.thumb
        PanelText(dc, c.busy ? "cleaning…" : hov ? "Choose a picture" : "No picture", 0, 0, w, wh, pnl.f["small"], LOOK.muted, 0x25)
    PanelText(dc, MOOD_NOTES[i], Dpx(4), wh + Dpx(10), w - Dpx(8), Dpx(22), pnl.f["cap"], LOOK.text)
    PanelText(dc, RangeText(i), Dpx(4), wh + Dpx(32), w - Dpx(8), Dpx(18), pnl.f["small"], LOOK.muted)
}

RangeText(i) {   ; "1–2 windows", "3–7 windows", "8+ windows"
    a := [1, pnl.some, pnl.many][i], b := [pnl.some - 1, pnl.many - 1, 0][i]
    return i = 3 ? a "+ windows" : a = b ? a (a = 1 ? " window" : " windows") : a "–" b " windows"
}

PaintStepper(i, dc, w, h, st) {   ; − value +; i: 2 = some starts at, 3 = many starts at, 4 = font size
    v := [0, pnl.some, pnl.many, pnl.size][i], lo := [0, 2, pnl.some + 1, 10][i], hi := [0, pnl.many - 1, 30, 24][i]
    side := st & 0x10000 ? pnl.side : 0, r := h / 2
    gr := Canvas(0, dc)
    FillRound(gr, 0.5, 0.5, w - 1, h - 1, r, Argb("F4EEE4", 255))
    if side && (side < 0 ? v > lo : v < hi)           ; the half under the mouse
        Disc(gr, side < 0 ? r : w - r, r, r - Dpx(3), Argb(LOOK.pill, 255))
    Stroke(gr, 0.5, 0.5, w - 1, h - 1, r, 1, Lip(220, LOOK.line, 210))
    FocusRing(gr, w, h, r, st)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    PanelText(dc, i = 4 ? v " pt" : v, 0, 0, w, h, pnl.f["num"], LOOK.text, 0x25)
    PanelText(dc, "−", 0, 0, 2 * r, h, pnl.f["body"], v > lo ? LOOK.muted : LOOK.faint, 0x25)
    PanelText(dc, "+", w - 2 * r, 0, 2 * r, h, pnl.f["body"], v < hi ? LOOK.muted : LOOK.faint, 0x25)
}

PaintChip(i, dc, w, h, st) {   ; "Clean" (background), a quiet pill
    hov := st & 0x10000, off := st & 4, gr := Canvas(0, dc), r := h / 2
    FillRound(gr, 0.5, 0.5, w - 1, h - 1, r, Argb(hov ? LOOK.pillHi : "FFFFFF", hov ? 255 : 150))
    Stroke(gr, 0.5, 0.5, w - 1, h - 1, r, 1, Lip(220, hov ? LOOK.pillRim : LOOK.line, 220))
    FocusRing(gr, w, h, r, st)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    PanelText(dc, "✧ Clean", 0, 0, w, h, pnl.f["small"], off ? LOOK.soft : LOOK.text, 0x25)
}

PaintButton(label, kind, dc, w, h, st) {   ; kind 0 = text link, 1 = quiet, 2 = primary (the switcher's selection pill)
    hov := st & 0x10000, down := st & 1, gr := Canvas(0, dc), r := h / 2
    if kind = 2 {
        FillRound(gr, 0.5, 0.5, w - 1, h - 1, r, Argb(down ? LOOK.pillRim : hov ? Mix(LOOK.pill, LOOK.pillRim, 0.45) : LOOK.pill, 255))
        Ring(gr, 0.5, 0.5, w - 1, h - 1, r, LOOK.pillRim, 255)
        DllCall("gdiplus\GdipCreatePen1", "uint", Argb(LOOK.pillHi, 255), "float", 1, "int", 2, "ptr*", &pen := 0)
        DllCall("gdiplus\GdipDrawLine", "ptr", gr, "ptr", pen, "float", r, "float", 2, "float", w - r, "float", 2)   ; glassy top highlight
        DllCall("gdiplus\GdipDeletePen", "ptr", pen)
    } else if kind = 1 {
        FillRound(gr, 0.5, 0.5, w - 1, h - 1, r, Argb("FFFFFF", down ? 230 : hov ? 200 : 110))
        Stroke(gr, 0.5, 0.5, w - 1, h - 1, r, 1, Lip(230, LOOK.line, 230))
    }
    FocusRing(gr, w, h, r, st)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    PanelText(dc, label, 0, 0, w, h, pnl.f[kind = 2 ? "num" : "body"], kind || hov ? LOOK.text : LOOK.muted, 0x25)
}

PaintHint(dc, w, h, st) {
    PanelText(dc, PanelHintText(), 0, 0, w, h, pnl.f["small"], LOOK.muted)
}

PanelHintText() {   ; hovered element's hint, else the last message, else the standing hint
    if pnl.hover && (e := pnl.el.Get(pnl.hover, 0)) && e.hint != ""
        return e.hint
    if pnl.note != ""
        return pnl.note
    return "Click a card to choose its picture, or drop one onto it."
}

; Peek scene j (1 = a single window at PEEK_MIN, 2 = many windows at PEEK_MAX): the picture behind the top
; edge of a small pane, raised by the same rule as ShowPeek (share of the ArtSpan rows above the edge).
PaintScene(j, dc, w, h, st) {
    c := pnl.cards[j = 1 ? 1 : 3], share := pnl.peek[j] / 100, lab := Dpx(24), sh := h - lab, r := Dpx(12)
    edge := sh - Dpx(30), d := Dpx(72), f := d / IMG_SIZE, px := Dpx(22)
    gr := Canvas(0, dc), well := RoundPath(0.5, 0.5, w - 1, sh - 1, r)   ; a soft well, like the cards'
    br := FadeBrush(0, 0, w, sh, 90, [[LOOK.wellTop, 140, 0], [LOOK.wellBot, 80, 1]])
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", well), DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    DllCall("gdiplus\GdipSetClipPath", "ptr", gr, "ptr", well, "int", 0)
    if c.big {
        DllCall("gdiplus\GdipSetInterpolationMode", "ptr", gr, "int", 7)
        top := edge - Round((c.span[1] + (c.span[2] - c.span[1]) * share) * f)
        DllCall("gdiplus\GdipDrawImageRectI", "ptr", gr, "ptr", c.big, "int", px + Dpx(12), "int", top, "int", d, "int", d)
    }
    pane := RoundPath(px + 0.5, edge + 0.5, w, sh, Dpx(8))   ; the pane's top-left corner; the well clips the rest
    br := FadeBrush(px, edge, w - px, sh - edge, 90, [[LOOK.bgTop, 255, 0], [LOOK.bg, 255, 0.6], [LOOK.bgBot, 255, 1]])
    DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", pane), DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    DllCall("gdiplus\GdipDeletePath", "ptr", pane)
    Ring(gr, px + 0.5, edge + 0.5, w, sh, Dpx(8), LOOK.border, 255)
    Ring(gr, px + 1.5, edge + 1.5, w, sh, Dpx(7), "FFFFFF", 200)
    FillRound(gr, px + Dpx(12), edge + Dpx(10), (w - px) * 0.5, Dpx(8), Dpx(4), Argb(LOOK.pill, 255))   ; list rows
    FillRound(gr, px + Dpx(12), edge + Dpx(22), (w - px) * 0.34, Dpx(4), Dpx(2), Argb(LOOK.line, 220))
    DllCall("gdiplus\GdipResetClip", "ptr", gr)
    Stroke(gr, 0.5, 0.5, w - 1, sh - 1, r, 1, Lip(210, LOOK.border, 120))
    DllCall("gdiplus\GdipDeletePath", "ptr", well), DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    PanelText(dc, j = 1 ? "1 window" : (pnl.many + 4) "+ windows", 0, sh, w / 2, lab, pnl.f["small"], LOOK.muted)
    PanelText(dc, pnl.peek[j] "%", w / 2, sh, w / 2, lab, pnl.f["num"], LOOK.text, 0x26)
}

PaintSlider(j, dc, w, h, st) {   ; track 30–100 %, filled to the knob; knob lit from the bottom-left
    r := Dpx(8), x0 := r + 1, x1 := w - r - 1, cy := h / 2, hot := st & 0x10000 || pnl.drag && pnl.el[pnl.drag].j = j
    cx := x0 + (pnl.peek[j] - 30) / 70 * (x1 - x0)
    gr := Canvas(0, dc)
    FillRound(gr, x0, cy - Dpx(2), x1 - x0, Dpx(4), Dpx(2), Argb("E7DDCC", 255))
    FillRound(gr, x0, cy - Dpx(2), Max(cx - x0, Dpx(4)), Dpx(4), Dpx(2), Argb(LOOK.accent, 170))
    Disc(gr, cx + 1, cy - 1, r + 1, Argb(LOOK.shadow, 22))           ; shadow, away from the light
    Disc(gr, cx, cy, r, Argb("FFFFFF", 255), Argb(hot ? LOOK.accent : LOOK.border, 255))
    if (st & 0x10) && !(st & 0x200)
        Disc(gr, cx, cy, r + Dpx(3), 0, Argb(LOOK.accent, 150))
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
}

PaintSample(dc, w, h, st) {   ; one list row in the chosen font, selected like in the switcher
    gr := Canvas(0, dc)
    FillRound(gr, 0.5, 0.5, w - 1, h - 1, Dpx(10), Argb(LOOK.card, 255))
    Stroke(gr, 0.5, 0.5, w - 1, h - 1, Dpx(10), 1, Lip(230, LOOK.line, 170))
    of := DllCall("SelectObject", "ptr", dc, "ptr", pnl.f["sample"], "ptr")
    sz := Buffer(8), DllCall("GetTextExtentPoint32W", "ptr", dc, "str", "Ag", "int", 2, "ptr", sz)
    title := "Visual Studio Code", tw := TextWidth(dc, title), DllCall("SelectObject", "ptr", dc, "ptr", of)
    rh := NumGet(sz, 4, "int") + Dpx(12), y := (h - rh) / 2
    FillRound(gr, Dpx(6), y, w - Dpx(12), rh, Dpx(7), Argb(LOOK.pill, 255))
    Ring(gr, Dpx(6) + 0.5, y + 0.5, w - Dpx(12) - 1, rh - 1, Dpx(7), LOOK.pillRim, 255)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    x := Dpx(20)
    PanelText(dc, title, x, y, tw, rh, pnl.f["sample"], LOOK.text)
    PanelText(dc, "   —   視窗 · ウィンドウ", x + tw, y, w - x - tw - Dpx(14), rh, pnl.f["sample"], LOOK.muted)
}
