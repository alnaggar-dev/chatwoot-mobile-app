#!/usr/bin/env python3
"""Build the DIN Next TTFs bundled in src/assets/fonts from the single Regular woff.

Only the Regular weight is available, so Medium and SemiBold are derived by
offsetting every outline outward (stroke + union), widening advances by the
same amount, and shifting GPOS anchors so Arabic marks stay attached.

Usage: python3 scripts/build-din-next-fonts.py <path/to/din-next.woff>
Requires: fonttools, skia-pathops
"""
import sys
from pathlib import Path

import pathops
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

OUT_DIR = Path(__file__).resolve().parent.parent / 'src/assets/fonts'
FAMILY = 'DIN Next LT W23'
PS_FAMILY = 'DINNextLTW23'
# (subfamily, usWeightClass, outline offset per side in font units; Regular stem is ~89)
WEIGHTS = [('Regular', 400, 0), ('Medium', 500, 11), ('SemiBold', 600, 22)]


def embolden_glyph(glyf, name, d):
    glyph = glyf[name]
    if glyph.isComposite() or glyph.numberOfContours == 0:
        return
    src = pathops.Path()
    glyph.draw(src.getPen(), glyf)
    stroke = pathops.Path(src)
    stroke.stroke(2 * d, pathops.LineCap.ROUND_CAP, pathops.LineJoin.ROUND_JOIN, 4)
    stroke.convertConicsToQuads()
    out = pathops.op(src, stroke, pathops.PathOp.UNION, fix_winding=True, keep_starting_points=False, clockwise=True)
    out.transform(1, 0, 0, 1, d, 0)
    tt = TTGlyphPen(glyf)
    out.draw(Cu2QuPen(tt, max_err=1.0))
    glyf[name] = tt.glyph()


def shift_anchor(anchor, d):
    if anchor is not None:
        anchor.XCoordinate += d


def shift_gpos_anchors(gpos, d):
    for lookup in gpos.LookupList.Lookup:
        for sub in lookup.SubTable:
            if hasattr(sub, 'ExtSubTable'):
                sub = sub.ExtSubTable
            if sub.LookupType == 3:
                for rec in sub.EntryExitRecord:
                    shift_anchor(rec.EntryAnchor, d)
                    shift_anchor(rec.ExitAnchor, d)
            elif sub.LookupType in (4, 5, 6):
                marks = (sub.Mark1Array if sub.LookupType == 6 else sub.MarkArray).MarkRecord
                for rec in marks:
                    shift_anchor(rec.MarkAnchor, d)
                if sub.LookupType == 4:
                    for rec in sub.BaseArray.BaseRecord:
                        for a in rec.BaseAnchor:
                            shift_anchor(a, d)
                elif sub.LookupType == 5:
                    for lig in sub.LigatureArray.LigatureAttach:
                        for comp in lig.ComponentRecord:
                            for a in comp.LigatureAnchor:
                                shift_anchor(a, d)
                else:
                    for rec in sub.Mark2Array.Mark2Record:
                        for a in rec.Mark2Anchor:
                            shift_anchor(a, d)


def set_names(font, subfamily, weight):
    ps_name = f'{PS_FAMILY}-{subfamily}'
    full = f'{FAMILY} {subfamily}'
    for rec in font['name'].names:
        value = {1: FAMILY, 2: subfamily, 3: f'{FAMILY}:{subfamily}', 4: full, 6: ps_name, 16: FAMILY, 17: subfamily}.get(rec.nameID)
        if value is not None:
            rec.string = value
    os2 = font['OS/2']
    os2.usWeightClass = weight
    os2.fsSelection = (os2.fsSelection & ~0b1100001) | (0b1000000 if subfamily == 'Regular' else 0)
    font['head'].macStyle &= ~0b11
    return ps_name


def build(src, subfamily, weight, d):
    font = TTFont(src)
    font.flavor = None
    if d:
        glyf, hmtx = font['glyf'], font['hmtx']
        for name in font.getGlyphOrder():
            embolden_glyph(glyf, name, d)
        for name in font.getGlyphOrder():
            g = glyf[name]
            g.recalcBounds(glyf)
            adv = hmtx[name][0]
            hmtx[name] = (adv + 2 * d if adv else 0, getattr(g, 'xMin', 0))
        shift_gpos_anchors(font['GPOS'].table, d)
        # Outlines were regenerated, so the TrueType hinting no longer applies.
        for tag in ('fpgm', 'prep', 'cvt '):
            if tag in font:
                del font[tag]
        glyf.removeHinting()
        font['OS/2'].recalcAvgCharWidth(font)
    ps_name = set_names(font, subfamily, weight)
    out = OUT_DIR / f'{ps_name}.ttf'
    font.save(out)
    print('wrote', out)


if __name__ == '__main__':
    src = sys.argv[1]
    for subfamily, weight, d in WEIGHTS:
        build(src, subfamily, weight, d)
