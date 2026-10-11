; Glass rendering, animation and accent helpers for peek-alttab.ahk (#Included by it; the
; settings, constants and state globals live there). Functions only, plus a guard against running it alone.

#Warn VarUnset, Off                                ; those globals don't exist when this file is opened by itself
if A_LineFile = A_ScriptFullPath {
    MsgBox "This file is #Included by peek-alttab.ahk and can't run alone. Run peek-alttab.ahk instead.", "alttab-glass", 0x10
    ExitApp
}
#Include %A_LineFile%\..\gdip-helpers.ahk   ; RoundPath, FadeBrush, Stroke, Canvas, FitBitmap, ArtSpan, ...

; ----- Pane animation: inhale on open, selection pill glide (ticks only move, fade or repaint rows) -----

; Fresh open: start faint (INHALE_A0) and INHALE_RISE px low, then InhaleStep eases in. Else settled, in place.
InhaleStart(fresh, x, y) {
    global paneA, paneDY, inhaleX := x, inhaleY := y, inhaleT := A_TickCount
    on := fresh && INHALE_MS > 0
    paneA := on ? INHALE_A0 : 255, paneDY := on ? INHALE_RISE : 0
    DllCall("SetLayeredWindowAttributes", "ptr", g.Hwnd, "uint", 0, "uchar", Round(paneA * PANE_A / 255), "uint", 2)   ; LWA_ALPHA
    SetTimer InhaleStep, on ? ANIM_TICK : 0
}

InhaleStep() {   ; one frame: pane and shadow alpha + the rise (the DWM thumbnail takes the pane's alpha)
    global paneA, paneDY
    p := Min((A_TickCount - inhaleT) / INHALE_MS, 1), e := 1 - (1 - p) ** 3   ; ease-out cubic
    paneA := Round(INHALE_A0 + (255 - INHALE_A0) * e), paneDY := Round(INHALE_RISE * (1 - e))
    DllCall("SetLayeredWindowAttributes", "ptr", g.Hwnd, "uint", 0, "uchar", Round(paneA * PANE_A / 255), "uint", 2)
    DllCall("SetWindowPos", "ptr", g.Hwnd, "ptr", 0, "int", inhaleX, "int", inhaleY + paneDY, "int", 0, "int", 0
        , "uint", 0x15)                                             ; NOSIZE|NOZORDER|NOACTIVATE
    DllCall("SetWindowPos", "ptr", listGui.Hwnd, "ptr", 0, "int", listX, "int", listY + paneDY, "int", 0, "int", 0
        , "uint", 0x15)                                             ; opaque list follows the pane's rise
    if SHADOW_A > 0
        Fade(shade, inhaleX - SHADOW_BLUR + SHADOW_DX, inhaleY + paneDY - SHADOW_BLUR + SHADOW_DY)
    if p < 1
        return
    SetTimer InhaleStep, 0
    if DllCall("IsWindowVisible", "ptr", peek.Hwnd)   ; the image waited, invisible, behind the faint pane
        Fade(peek), PeekStart()                       ; (it would show through): now it peeks out
}

; Set a layered window's constant alpha to paneA (and move it), keeping its content.
Fade(win, x := "", y := "") {
    DllCall("UpdateLayeredWindow", "ptr", win.Hwnd, "ptr", 0, x = "" ? "ptr" : "int64*", x = "" ? 0 : (y << 32) | (x & 0xFFFFFFFF)
        , "ptr", 0, "ptr", 0, "ptr", 0, "uint", 0, "uint*", 0x01000000 | paneA << 16, "uint", 2)   ; src-alpha blend, ULW_ALPHA
}

; Show the fully opaque list at its reserved client position; ownership keeps it above the translucent pane.
ShowListCard() {
    global listX, listY
    g.GetClientPos(&x, &y), listSlot.GetPos(&lx, &ly, &w, &h)
    listX := x + lx, listY := y + ly - paneDY
    listGui.Show("NA x" listX " y" (listY + paneDY) " w" w " h" h)
}

; Highlight row i now; the pill then glides there from a nearby visible row (cosmetic only) or snaps.
Select(i) {
    global pillRow, glideFrom, glideTo, glideT
    SetTimer GlideStep, 0
    from := pillRow
    lb.Choose(i)                                   ; may scroll; rows repaint with the pill still at `from`
    if GLIDE_MS > 0 && from && Abs(i - from) <= GLIDE_MAX_ROWS && RowShown(from) && RowShown(i) {
        glideFrom := from, glideTo := i, glideT := A_TickCount
        return SetTimer(GlideStep, ANIM_TICK)
    }
    pillRow := i, RepaintRows(from, i)
}

GlideStep() {   ; one frame: move the pill (in rows) and repaint just the rows it crossed
    global pillRow
    p := Min((A_TickCount - glideT) / GLIDE_MS, 1), old := pillRow
    pillRow := p >= 1 ? glideTo : glideFrom + (glideTo - glideFrom) * (1 - (1 - p) ** 3)
    if p >= 1
        SetTimer GlideStep, 0
    RepaintRows(old, pillRow)
}

RowShown(r) {   ; row r (rounded) is in the list's visible window
    top := SendMessage(0x18E, 0, 0, lb) + 1        ; LB_GETTOPINDEX
    lb.GetPos(, , , &h)
    return (r := Round(r)) >= top && r < top + h // SendMessage(0x1A1, 0, 0, lb)
}

; Redraw, without erase, the rows a pill at row positions a and b touches (0 = no pill).
RepaintRows(a, b) {
    lo := Max(Floor(a && b ? Min(a, b) : a + b), 1), hi := Min(Ceil(Max(a, b)), rows.Length)
    if lo > hi
        return
    rc := Buffer(16), r2 := Buffer(16)
    SendMessage(0x198, lo - 1, rc.Ptr, lb), SendMessage(0x198, hi - 1, r2.Ptr, lb)   ; LB_GETITEMRECT
    NumPut("int", NumGet(r2, 12, "int"), rc, 12)
    DllCall("InvalidateRect", "ptr", lb.Hwnd, "ptr", rc, "int", false), DllCall("UpdateWindow", "ptr", lb.Hwnd)
}

; Selection pill with a 1px rim and a glassy highlight line just inside its top edge; t, b = its row.
Pill(dc, l, t, r, b) {
    br := DllCall("CreateSolidBrush", "uint", Bgr(PILL_RGB), "ptr")
    rim := DllCall("CreatePen", "int", 0, "int", 1, "uint", Bgr(PILL_RIM), "ptr")   ; PS_SOLID
    hi := DllCall("CreatePen", "int", 0, "int", 1, "uint", Bgr(PILL_HI), "ptr")
    ob := DllCall("SelectObject", "ptr", dc, "ptr", br, "ptr"), op := DllCall("SelectObject", "ptr", dc, "ptr", rim, "ptr")
    DllCall("RoundRect", "ptr", dc, "int", l + 4, "int", t + PILL_INSET, "int", r - 4, "int", b - PILL_INSET, "int", PILL_R, "int", PILL_R)
    DllCall("SelectObject", "ptr", dc, "ptr", hi, "ptr"), DllCall("MoveToEx", "ptr", dc, "int", l + 16, "int", t + PILL_INSET + 1, "ptr", 0)
    DllCall("LineTo", "ptr", dc, "int", r - 16, "int", t + PILL_INSET + 1)
    DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("SelectObject", "ptr", dc, "ptr", op)
    DllCall("DeleteObject", "ptr", br), DllCall("DeleteObject", "ptr", rim), DllCall("DeleteObject", "ptr", hi)
}

; ----- Vibrancy accent: a pastel of the selected app's icon colour, as a halo around the preview well -----

SetAccent(hwnd) {   ; tint the well for hwnd's app; repaints only that part of the pane
    global accentRgb
    if !glassBase                                  ; accent off, or no glass yet
        return
    accentRgb := AccentOf(hwnd)
    if !GlassAccent(accentRgb)
        return
    AccentRect(&x, &y, &w, &h), listSlot.GetPos(&lx, &ly, &lw, &lh)   ; repaint the pane but not the list, which hides the glass anyway
    rgn := DllCall("CreateRectRgn", "int", x, "int", y, "int", x + w, "int", y + h, "ptr")
    lr := DllCall("CreateRectRgn", "int", lx, "int", ly, "int", lx + lw, "int", ly + lh, "ptr")
    DllCall("CombineRgn", "ptr", rgn, "ptr", rgn, "ptr", lr, "int", 4)   ; RGN_DIFF
    DllCall("RedrawWindow", "ptr", g.Hwnd, "ptr", 0, "ptr", rgn, "uint", 0x85)   ; INVALIDATE|ERASE|ALLCHILDREN: caption redraws over it
    DllCall("DeleteObject", "ptr", rgn), DllCall("DeleteObject", "ptr", lr)
}

AccentOf(hwnd) {   ; "RRGGBB" or "" (no icon / nearly grey), sampled once per process path
    try path := WinGetProcessPath(hwnd)
    catch
        return ""
    if accents.Has(path)
        return accents[path]
    c := IconColor(hwnd)
    if !IsObject(c) && c = -1                      ; app busy: no accent now, retry next time
        return ""
    return accents[path] := Pastel(c)
}

; Alpha-weighted mean colour of hwnd's icon as [r, g, b] 0-1; 0 = no icon, -1 = timed out. The icon is borrowed, not freed.
IconColor(hwnd) {
    for t in [1, 2, 0] {                           ; ICON_BIG, ICON_SMALL2, ICON_SMALL; a hung app can't stall us
        if !DllCall("SendMessageTimeoutW", "ptr", hwnd, "uint", 0x7F, "ptr", t, "ptr", 0, "uint", 2, "uint", 20
            , "ptr*", &hi := 0)                    ; WM_GETICON, SMTO_ABORTIFHUNG
            return -1
        if hi
            break
    }
    hi := hi || DllCall("GetClassLongPtrW", "ptr", hwnd, "int", -14, "ptr") || DllCall("GetClassLongPtrW", "ptr", hwnd, "int", -34, "ptr")
    if !hi                                         ; GCLP_HICON / GCLP_HICONSM
        return 0
    bi := Buffer(40, 0), NumPut("uint", 40, "int", 32, "int", -32, "ushort", 1, "ushort", 32, bi)   ; 32x32 32bpp top-down
    dc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    hbm := DllCall("CreateDIBSection", "ptr", dc, "ptr", bi, "uint", 0, "ptr*", &bits := 0, "ptr", 0, "uint", 0, "ptr")
    ob := DllCall("SelectObject", "ptr", dc, "ptr", hbm, "ptr")
    DllCall("DrawIconEx", "ptr", dc, "int", 0, "int", 0, "ptr", hi, "int", 32, "int", 32, "uint", 0, "ptr", 0, "uint", 3)   ; DI_NORMAL
    sa := sr := sg := sb := n := 0
    Loop 1024 {                                    ; alpha icons come out premultiplied: sum(c) / sum(a) = weighted mean
        px := NumGet(bits, 4 * A_Index - 4, "uint")
        sa += px >> 24, sr += px >> 16 & 0xFF, sg += px >> 8 & 0xFF, sb += px & 0xFF, n += (px & 0xFFFFFF) != 0
    }
    DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("DeleteObject", "ptr", hbm), DllCall("DeleteDC", "ptr", dc)
    d := sa ? sa : n * 255                         ; old mask icons have no alpha: mean of the non-black pixels
    return d ? [sr / d, sg / d, sb / d] : 0
}

; [r, g, b] 0-1 -> "RRGGBB" pastel of the same hue (ACCENT_S, ACCENT_L) warmed toward ACCENT_WARM, or "" when (nearly) grey.
Pastel(c) {
    if !c
        return ""
    mx := Max(c*), mn := Min(c*), d := mx - mn, l := (mx + mn) / 2
    if d = 0 || d / (1 - Abs(2 * l - 1)) < ACCENT_MIN_S
        return ""
    h := mx = c[1] ? Mod((c[2] - c[3]) / d + 6, 6) : mx = c[2] ? (c[3] - c[1]) / d + 2 : (c[1] - c[2]) / d + 4   ; hue 0-6
    a := ACCENT_S * Min(ACCENT_L, 1 - ACCENT_L), warm := Integer("0x" ACCENT_WARM), out := ""
    for i, n in [0, 8, 4] {                        ; HSL -> R, G, B, each mixed toward the warm tone
        k := Mod(n + 2 * h, 12), v := 255 * (ACCENT_L - a * Max(-1, Min(k - 3, 9 - k, 1)))
        out .= Format("{:02X}", Round(v + ((warm >> (24 - 8 * i) & 0xFF) - v) * ACCENT_WARM_MIX))
    }
    return out
}

AccentRect(&x, &y, &w, &h) {   ; client rect the accent can touch: the whole pane (the spill reaches under the list)
    x := y := 0, g.GetClientPos(, , &w, &h)
}

; Restore the well's surroundings in the cached glass from their accent-free copy (baseDC), then draw
; rgb's halo ("" = none) straight onto it. Returns true when the cache changed.
GlassAccent(rgb) {
    global accentKey
    if !glassBase || accentKey = glassKey "|" rgb
        return false
    AccentRect(&x, &y, &w, &h)
    DllCall("BitBlt", "ptr", glassDC, "int", x, "int", y, "int", w, "int", h, "ptr", baseDC, "int", 0, "int", 0, "uint", 0xCC0020)   ; SRCCOPY
    if rgb != "" {
        pv.GetPos(&x, &y, &w, &h), g.GetClientPos(, , &cw, &ch)
        x -= WELL_PAD, y -= WELL_PAD, w += 2 * WELL_PAD, h += 2 * WELL_PAD   ; the well
        bloom := Mix(rgb, ACCENT_WARM, 0.5)        ; the lit bottom-left corner blooms warmer; the rest keeps the app's hue
        if ACCENT_SPILL_A                          ; the screen's light spilling onto the glass, toward the open bottom-left
            Spill(x, y + h * 0.6, ACCENT_SPILL * cw, ch, cw, ch, [[rgb, ACCENT_SPILL_A, 0]
                , [rgb, ACCENT_SPILL_A * 9 // 20, 0.45], [bloom, 0, 1]])
        gr := Canvas(0, glassDC)                   ; after Spill: GDI and GDI+ don't share the DC at once
        Loop Ceil(ACCENT_W / 2) {                  ; ambient glow: 2px rings (half the draws), Gaussian falloff
            k := 2 * A_Index - 1, a := Round(ACCENT_A * Exp(-4.5 * (k / ACCENT_W) ** 2))
            if a
                Stroke(gr, x - k, y - k, w + 2 * k, h + 2 * k, WELL_R + k, 2
                    , [[bloom, a, 0], [rgb, a, 0.3], [rgb, a, 1]], LIGHT_ANGLE)
        }
        if ACCENT_FILL_A {                         ; soft wash inside the well: lit from within, strongest at the top-right
            path := RoundPath(x, y, w, h, WELL_R)
            DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br := FadeBrush(x, y, w, h, LIGHT_ANGLE
                , [[bloom, ACCENT_FILL_A // 2, 0], [rgb, ACCENT_FILL_A, 1]]), "ptr", path)
            DllCall("gdiplus\GdipDeleteBrush", "ptr", br), DllCall("gdiplus\GdipDeletePath", "ptr", path)
        }
        if ACCENT_LIP_A                            ; tint the well's top/right edge; the lit lip stays white
            Stroke(gr, x + 0.5, y + 0.5, w - 1, h - 1, WELL_R, 1, Lip(0, rgb, ACCENT_LIP_A), LIGHT_ANGLE)
        DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    }
    accentKey := glassKey "|" rgb
    return true
}

; Radial glow (as RadialFill) blended onto glassDC, clipped to the cw x ch pane. A smooth gradient loses
; nothing at quarter resolution, so it is drawn small and stretched: ~16x less GDI+ work.
Spill(cx, cy, rx, ry, cw, ch, stops) {
    static S := 4
    x0 := Max(0, Floor(cx - rx)), x1 := Min(cw, Ceil(cx + rx)), y0 := Max(0, Floor(cy - ry)), y1 := Min(ch, Ceil(cy + ry))
    if x1 <= x0 || y1 <= y0
        return
    sw := Ceil((x1 - x0) / S), sh := Ceil((y1 - y0) / S), bm := NewBitmap(sw, sh), gr := Canvas(bm)
    RadialFill(gr, (cx - x0) / S, (cy - y0) / S, rx / S, ry / S, stops)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    hbm := ToHbm(bm), dc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr"), ob := DllCall("SelectObject", "ptr", dc, "ptr", hbm, "ptr")
    DllCall("SetStretchBltMode", "ptr", glassDC, "int", 4)   ; HALFTONE
    DllCall("msimg32\AlphaBlend", "ptr", glassDC, "int", x0, "int", y0, "int", x1 - x0, "int", y1 - y0
        , "ptr", dc, "int", 0, "int", 0, "int", sw, "int", sh, "uint", 0x01FF0000)   ; AC_SRC_OVER, 255, AC_SRC_ALPHA
    DllCall("SelectObject", "ptr", dc, "ptr", ob), DllCall("DeleteDC", "ptr", dc), DllCall("DeleteObject", "ptr", hbm)
}

; ----- Layered windows: image and shadow -----

; Give a layered window premultiplied 32bpp content hbm (w x h) at screen x, y, faded to constant alpha a.
Layer(win, hbm, x, y, w, h, a := 255) {
    hdc := DllCall("CreateCompatibleDC", "ptr", 0, "ptr")
    ob := DllCall("SelectObject", "ptr", hdc, "ptr", hbm, "ptr")
    DllCall("UpdateLayeredWindow", "ptr", win.Hwnd, "ptr", 0, "int64*", (y << 32) | (x & 0xFFFFFFFF)
        , "int64*", (h << 32) | w, "ptr", hdc, "int64*", 0, "uint", 0
        , "uint*", 0x01000000 | a << 16, "uint", 2)                 ; BLENDFUNCTION src-alpha, ULW_ALPHA
    DllCall("SelectObject", "ptr", hdc, "ptr", ob), DllCall("DeleteDC", "ptr", hdc)
}

; Warm soft drop shadow in its own click-through window, offset away from the light.
ShowShadow(w, h) {
    if SHADOW_A <= 0
        return shade.Hide()
    ShadowBitmap(w, h), b := SHADOW_BLUR
    g.GetPos(&x, &y)
    Layer(shade, shadeBmp, x - b + SHADOW_DX, y - b + SHADOW_DY, w + 2 * b, h + 2 * b, paneA)
    DllCall("SetWindowPos", "ptr", shade.Hwnd, "ptr", g.Hwnd, "int", 0, "int", 0, "int", 0, "int", 0
        , "uint", 0x53)                                             ; just below the pane: NOSIZE|NOMOVE|NOACTIVATE|SHOWWINDOW
}

; The shadow of a w x h pane (shadeBmp, cached by size): fades from the outline (alpha 0) to b px inside
; the pane. Only that ring needs the gradient; the flat centre is one solid fill (same pixels, ~3x faster).
ShadowBitmap(w, h) {
    global shadeBmp, shadeKey
    if SHADOW_A <= 0 || shadeKey = w "x" h
        return
    b := SHADOW_BLUR, sw := w + 2 * b, sh := h + 2 * b, c := 3 * b + PANE_R   ; c: inset of the flat centre
    gr := Canvas(bm := PBitmap(sw, sh)), path := RoundPath(0, 0, sw, sh, PANE_R + b), flat := sw > 2 * c && sh > 2 * c
    if flat
        DllCall("gdiplus\GdipSetClipRectI", "ptr", gr, "int", c, "int", c, "int", sw - 2 * c, "int", sh - 2 * c, "int", 4)   ; Exclude
    EdgeFade(gr, path, SHADOW_RGB, 0, SHADOW_A, (w - 2 * b) / sw, (h - 2 * b) / sh, true)
    if flat {
        DllCall("gdiplus\GdipResetClip", "ptr", gr)
        DllCall("gdiplus\GdipCreateSolidFill", "uint", Argb(SHADOW_RGB, SHADOW_A), "ptr*", &br := 0)
        DllCall("gdiplus\GdipFillRectangleI", "ptr", gr, "ptr", br, "int", c, "int", c, "int", sw - 2 * c, "int", sh - 2 * c)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", br)
    }
    DllCall("gdiplus\GdipDeletePath", "ptr", path), DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    if shadeBmp
        DllCall("DeleteObject", "ptr", shadeBmp)
    shadeBmp := ToHbm(bm), shadeKey := w "x" h
}

; Image file -> sz x sz 32bpp HBITMAP (FitBitmap: bicubic, aspect kept). Transparent background = alpha kept.
; 0 = failed. span gets the [top, bottom] rows of the visible art, so a peek can ignore transparent padding.
ScaledBitmap(file, sz, &span := 0) {
    span := [0, sz]
    if !bm := FitBitmap(file, sz)
        return 0                    ; missing or unreadable
    span := ArtSpan(bm, sz)
    return ToHbm(bm)
}

; ----- The glass pane: cached GDI+ layers blitted on WM_ERASEBKGND -----

; WM_ERASEBKGND: blit the cached glass onto the pane (other windows keep the default).
EraseBg(wParam, lParam, msg, hwnd) {
    if hwnd != g.Hwnd || !glassBmp
        return
    g.GetClientPos(, , &w, &h)
    DllCall("BitBlt", "ptr", wParam, "int", 0, "int", 0, "int", w, "int", h, "ptr", glassDC, "int", 0, "int", 0, "uint", 0xCC0020)   ; SRCCOPY
    return 1
}

; Re-render the glass only when the pane or list size changed; it lives in glassDC. The costly
; smooth layers (the plate) depend on the pane size only, so a new window count just redraws
; the insets and grain on a copy of it. The well's accent-free surroundings are kept (glassBase in baseDC)
; so the accent halo can be redrawn without re-rendering anything else.
GlassRender(w, h, listH) {
    global glassBmp, glassKey, plate, plateKey, glassBase
    if glassKey = (key := w "x" h "x" listH)
        return
    if plateKey != w "x" h {
        if plate
            DllCall("gdiplus\GdipDisposeImage", "ptr", plate)
        plate := PaintPlate(w, h), plateKey := w "x" h
    }
    DllCall("gdiplus\GdipCloneBitmapAreaI", "int", 0, "int", 0, "int", w, "int", h, "int", 0xE200B, "ptr", plate, "ptr*", &bm := 0)   ; PARGB as the plate
    gr := Canvas(bm)
    PaintInsets(gr)
    DllCall("gdiplus\GdipSetPixelOffsetMode", "ptr", gr, "int", 3)   ; None: the texture fill is 15x faster
    if grainBr
        Fill(gr, grainBr, w, h, false)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    hbm := ToHbm(bm)
    DllCall("SelectObject", "ptr", glassDC, "ptr", hbm, "ptr")   ; 1st time returns the stock bitmap: leave it be
    if glassBmp
        DllCall("DeleteObject", "ptr", glassBmp)
    glassBmp := hbm, glassKey := key
    if pv && (ACCENT_A > 0 || ACCENT_LIP_A > 0) {   ; keep the accent-free well surroundings for re-tinting
        AccentRect(&x, &y, &rw, &rh), b := DllCall("CreateCompatibleBitmap", "ptr", glassDC, "int", rw, "int", rh, "ptr")
        DllCall("SelectObject", "ptr", baseDC, "ptr", b, "ptr")   ; 1st time returns the stock bitmap
        if glassBase
            DllCall("DeleteObject", "ptr", glassBase)
        glassBase := b
        DllCall("BitBlt", "ptr", baseDC, "int", 0, "int", 0, "int", rw, "int", rh, "ptr", glassDC, "int", x, "int", y, "uint", 0xCC0020)
        GlassAccent(accentRgb)                  ; the halo isn't in the base: put it back
    }
}

; The glass layers, bottom to top, as a new w x h GDI+ bitmap (caller disposes it). The broad gradients are
; drawn at 1/S size and stretched (as Spill: within 3 levels of full size, ~2-3x faster); the glow's inner
; edge and the rim are drawn full size.
PaintPlate(w, h) {
    static S := 4
    sw := Ceil(w / S), sh := Ceil(h / S), gr := Canvas(lo := PBitmap(sw, sh))
    DllCall("gdiplus\GdipScaleWorldTransform", "ptr", gr, "float", sw / w, "float", sh / h, "int", 0)   ; draw in pane px
    Fill(gr, FadeBrush(0, 0, w, h, 90, [[BASE_TOP, 255, 0], [BASE_MID, 255, 0.5], [BASE_BOT, 255, 1]]), w, h)   ; unclipped: no dark corners
    pane := RoundPath(0, 0, w, h, PANE_R)
    DllCall("gdiplus\GdipSetClipPath", "ptr", gr, "ptr", pane, "int", 0)   ; CombineModeReplace
    RadialFill(gr, w, 0, SHADE_RX * w, SHADE_RY * h, [[SHADE_RGB, SHADE_A, 0], [SHADE_RGB, 0, 1]])
    Fill(gr, FadeBrush(0, 0, w, h, 90, [["FFFFFF", SHEEN_A, 0], ["FFFFFF", 0, SHEEN_H], ["FFFFFF", 0, 1]]), w, h)
    RadialFill(gr, 0, h, BLOOM_RX * w, BLOOM_RY * h, BLOOM)
    Fill(gr, FadeBrush(0, 0, w, h, LIGHT_ANGLE, [["FFFFFF", REFLECT_A, 0], ["FFFFFF", 0, REFLECT_EXT], ["FFFFFF", 0, 1]]), w, h)
    DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    gr := Canvas(bm := PBitmap(w, h)), Upscale(gr, lo, sw, sh, w, h)
    DllCall("gdiplus\GdipSetClipPath", "ptr", gr, "ptr", pane, "int", 0)
    DllCall("gdiplus\GdipSetClipRectI", "ptr", gr, "int", GLOW_W, "int", GLOW_W, "int", w - 2 * GLOW_W, "int", h - 2 * GLOW_W
        , "int", 4)                         ; CombineModeExclude: the glow's clear centre needs no fill
    EdgeFade(gr, pane, GLOW_RGB, GLOW_A, 0, 1 - 2 * GLOW_W / w, 1 - 2 * GLOW_W / h)
    DllCall("gdiplus\GdipSetClipPath", "ptr", gr, "ptr", pane, "int", 0)
    i := 1 + RIM_W / 2                      ; just inside the DWM border
    Stroke(gr, i, i, w - 2 * i, h - 2 * i, RIM_R, RIM_W, [["FFFFFF", RIM_A0, 0], ["FFFFFF", RIM_A1, 1]], LIGHT_ANGLE)
    DllCall("gdiplus\GdipDeletePath", "ptr", pane), DllCall("gdiplus\GdipDeleteGraphics", "ptr", gr)
    return bm
}

Upscale(gr, src, sw, sh, w, h) {   ; copy sw x sh bitmap src (disposed) over 0, 0, w, h, smoothly stretched
    DllCall("gdiplus\GdipCreateImageAttributes", "ptr*", &ia := 0)
    DllCall("gdiplus\GdipSetImageAttributesWrapMode", "ptr", ia, "int", 3, "uint", 0, "int", 0)   ; TileFlipXY: edges keep their colour
    DllCall("gdiplus\GdipSetInterpolationMode", "ptr", gr, "int", 6)   ; HighQualityBilinear (plain Bilinear is 3x slower here)
    DllCall("gdiplus\GdipSetCompositingMode", "ptr", gr, "int", 1)     ; SourceCopy
    DllCall("gdiplus\GdipDrawImageRectRect", "ptr", gr, "ptr", src, "float", 0, "float", 0, "float", w, "float", h
        , "float", 0, "float", 0, "float", sw, "float", sh, "int", 2, "ptr", ia, "ptr", 0, "ptr", 0)   ; UnitPixel
    DllCall("gdiplus\GdipSetCompositingMode", "ptr", gr, "int", 0)     ; SourceOver
    DllCall("gdiplus\GdipDisposeImageAttributes", "ptr", ia), DllCall("gdiplus\GdipDisposeImage", "ptr", src)
}

; New w x h premultiplied 32bpp GDI+ bitmap: GDI+ draws into it fastest and ToHbm needs no conversion.
PBitmap(w, h) => (DllCall("gdiplus\GdipCreateBitmapFromScan0", "int", w, "int", h, "int", 0, "int", 0xE200B   ; 32bppPARGB
    , "ptr", 0, "ptr*", &bm := 0), bm)

; Preview well around the thumbnail area and a hairline around the list card (client coords).
PaintInsets(gr) {
    if pv {
        pv.GetPos(&x, &y, &w, &h)
        x -= WELL_PAD, y -= WELL_PAD, w += 2 * WELL_PAD, h += 2 * WELL_PAD
        path := RoundPath(x, y, w, h, WELL_R)
        br := FadeBrush(x, y, w, h, 90, [[WELL_TOP, WELL_TOP_A, 0], [WELL_BOT, WELL_BOT_A, 1]])
        DllCall("gdiplus\GdipFillPath", "ptr", gr, "ptr", br, "ptr", path)
        DllCall("gdiplus\GdipDeleteBrush", "ptr", br), DllCall("gdiplus\GdipDeletePath", "ptr", path)
        Stroke(gr, x + 0.5, y + 0.5, w - 1, h - 1, WELL_R, 1, Lip(WELL_LIP_A, BORDER, WELL_LINE_A), LIGHT_ANGLE)
    }
    listSlot.GetPos(&x, &y, &w, &h)
    Stroke(gr, x - 0.5, y - 0.5, w + 1, h + 1, CARD_R / 2 + 0.5, 1, Lip(CARD_LIP_A, CARD_LINE, CARD_LINE_A), LIGHT_ANGLE)
}

; Frosted grain: 128x128 tile of faint black / white specks as a texture brush (0 = off).
MakeGrain(amp) {
    if amp <= 0
        return 0
    bm := NewBitmap(128, 128), bd := Buffer(32, 0)   ; BitmapData
    rc := Buffer(16), NumPut("int", 0, "int", 0, "int", 128, "int", 128, rc)
    DllCall("gdiplus\GdipBitmapLockBits", "ptr", bm, "ptr", rc, "uint", 2, "int", 0x26200A, "ptr", bd)   ; ImageLockModeWrite
    stride := NumGet(bd, 8, "int"), p := NumGet(bd, 16, "ptr")
    Loop 128 {
        row := p + (A_Index - 1) * stride
        Loop 128                             ; ~amp levels either way on mid tones
            NumPut("uint", Random(0, 2 * amp) << 24 | (Random(0, 1) ? 0xFFFFFF : 0), row, 4 * A_Index - 4)
    }
    DllCall("gdiplus\GdipBitmapUnlockBits", "ptr", bm, "ptr", bd)
    DllCall("gdiplus\GdipCreateTexture", "ptr", bm, "int", 0, "ptr*", &br := 0)   ; WrapModeTile; copies the image
    DllCall("gdiplus\GdipDisposeImage", "ptr", bm)
    return br
}
