"""Notation tools for MuseScore MCP (added 23-Sep-2026, verified against MuseScore Studio 4.7.5).

Dynamics, chord symbols, texts, tempo marks, key signatures, articulations, ties, slurs, hairpins,
ottavas, transposition, durations, save/export, bar-range reads and annotation removal.
Every write answers with a FRESH selection state; read a bar range with get_measures to verify.
"""

from typing import List, Optional

from ..client import MuseScoreClient


def _range(start_tick, end_tick, staff, end_staff):
    p = {}
    if start_tick is not None:
        p["startTick"] = start_tick
    if end_tick is not None:
        p["endTick"] = end_tick
    if staff is not None:
        p["staff"] = staff
    if end_staff is not None:
        p["endStaff"] = end_staff
    return p


def _at(tick, staff, voice):
    p = {}
    if tick is not None:
        p["tick"] = tick
    if staff is not None:
        p["staff"] = staff
    if voice is not None:
        p["voice"] = voice
    return p


def setup_notation_tools(mcp, client: MuseScoreClient):
    """Setup notation tools."""

    @mcp.tool()
    async def get_selection():
        """Re-read MuseScore's current selection (tick, staff, the chords/rests inside it)."""
        return await client.send_command("getSelection", {})

    @mcp.tool()
    async def get_measures(from_measure: int = 1, to_measure: Optional[int] = None, annotations: bool = True):
        """Read a range of bars (1-based, inclusive): every chord/rest per staff and voice with ticks,
        pitches, ties and articulations; the bar's annotations (dynamics, chord symbols, texts, tempo,
        rehearsal marks, fermatas); spanners overlapping the range (slurs, hairpins, ottavas, pedal).
        Cheap alternative to get_score. Use it to verify after every write batch.
        """
        params = {"from": from_measure, "to": to_measure if to_measure is not None else from_measure, "annotations": annotations}
        return await client.send_command("getMeasures", params)

    @mcp.tool()
    async def add_dynamic(text: str = "mf", tick: Optional[int] = None, staff: Optional[int] = None, velocity: Optional[int] = None):
        """Add a dynamic (pp, p, mp, mf, f, ff, sfz ...) at the cursor or at an explicit tick/staff."""
        params = {"kind": "dynamic", "text": text, **_at(tick, staff, None)}
        if velocity is not None:
            params["velocity"] = velocity
        return await client.send_command("addAnnotation", params)

    @mcp.tool()
    async def add_chord_symbol(text: str, tick: Optional[int] = None, staff: Optional[int] = None):
        """Add a chord symbol (Gm, D7, Cmaj7, Bb/D ...) at the cursor or at an explicit tick/staff."""
        return await client.send_command("addAnnotation", {"kind": "chordSymbol", "text": text, **_at(tick, staff, None)})

    @mcp.tool()
    async def add_text(text: str, kind: str = "staffText", tick: Optional[int] = None, staff: Optional[int] = None):
        """Add a text at the cursor or at an explicit tick/staff.

        Args:
            kind: staffText | systemText | rehearsalMark | expression
        """
        return await client.send_command("addAnnotation", {"kind": kind, "text": text, **_at(tick, staff, None)})

    @mcp.tool()
    async def add_tempo_mark(bpm: float, text: Optional[str] = None, tick: Optional[int] = None, staff: Optional[int] = None):
        """Add a tempo mark (playback bpm + the printed text, default 'q = bpm' style) at the cursor or tick."""
        params = {"kind": "tempo", "bpm": bpm, "text": text if text else f"= {bpm:g}", **_at(tick, staff, None)}
        return await client.send_command("addAnnotation", params)

    @mcp.tool()
    async def set_key_signature(key: int, tick: Optional[int] = None, all_staves: bool = True, staff: Optional[int] = None):
        """Set a key signature at the cursor's bar (or at tick).

        Args:
            key: number of fifths, -7 (Cb) .. -2 (Bb / Gm) .. 0 (C / Am) .. 2 (D / Bm) .. 7 (C#)
            all_staves: apply to every staff (default) or only to `staff`
        """
        params = {"key": key, "allStaves": all_staves}
        if tick is not None:
            params["tick"] = tick
        if staff is not None:
            params["staff"] = staff
        return await client.send_command("setKeySignature", params)

    @mcp.tool()
    async def add_articulation(type: str = "staccato", start_tick: Optional[int] = None, end_tick: Optional[int] = None,
                               staff: Optional[int] = None, end_staff: Optional[int] = None):
        """Toggle an articulation on every chord in a tick range (default: the current selection).

        Args:
            type: staccato | tenuto | marcato | accent
            end_staff: exclusive, as in MuseScore (default staff + 1)
        """
        return await client.send_command("addArticulation", {"type": type, **_range(start_tick, end_tick, staff, end_staff)})

    @mcp.tool()
    async def add_tie(start_tick: Optional[int] = None, end_tick: Optional[int] = None, staff: Optional[int] = None):
        """Tie every note in the range to the following note of the same pitch (default: the current selection).
        Nothing happens for a note with no same-pitch successor."""
        return await client.send_command("addTie", _range(start_tick, end_tick, staff, None))

    @mcp.tool()
    async def add_slur(start_tick: int, end_tick: int, staff: Optional[int] = None):
        """Add a slur from the first to the last chord inside the tick range on one staff."""
        return await client.send_command("addSlur", _range(start_tick, end_tick, staff, None))

    @mcp.tool()
    async def add_hairpin(start_tick: int, end_tick: int, staff: Optional[int] = None, type: str = "crescendo"):
        """Add a hairpin over the tick range. type: crescendo | diminuendo."""
        return await client.send_command("addHairpin", {"type": type, **_range(start_tick, end_tick, staff, None)})

    @mcp.tool()
    async def add_ottava(start_tick: int, end_tick: int, staff: Optional[int] = None, type: str = "8va"):
        """Add an ottava line over the tick range. type: 8va | 8vb."""
        return await client.send_command("addOttava", {"type": type, **_range(start_tick, end_tick, staff, None)})

    @mcp.tool()
    async def transpose(start_tick: int, end_tick: int, semitones: int = 0, octaves: int = 0,
                        staff: Optional[int] = None, end_staff: Optional[int] = None):
        """Transpose every note in the tick range by signed semitones and/or octaves (MuseScore respells).
        end_staff is exclusive (default staff + 1)."""
        return await client.send_command("transpose", {"semitones": semitones, "octaves": octaves, **_range(start_tick, end_tick, staff, end_staff)})

    @mcp.tool()
    async def set_duration(numerator: int, denominator: int, tick: Optional[int] = None, staff: Optional[int] = None, voice: Optional[int] = None):
        """Change the duration of the chord or rest at the cursor (or at tick/staff/voice), like the GUI:
        lengthening eats the rests that follow, shortening leaves a rest."""
        return await client.send_command("setDuration", {"numerator": numerator, "denominator": denominator, **_at(tick, staff, voice)})

    @mcp.tool()
    async def delete_range(start_tick: int, end_tick: int, staff: Optional[int] = None, end_staff: Optional[int] = None):
        """Delete everything in the tick range (notes become rests). end_staff exclusive (default staff + 1)."""
        return await client.send_command("deleteSelection", _range(start_tick, end_tick, staff, end_staff))

    @mcp.tool()
    async def remove_annotations(start_tick: int, end_tick: int, staff: Optional[int] = None, kinds: Optional[List[str]] = None):
        """Remove annotations in the tick range on one staff.

        Args:
            kinds: element names to remove, e.g. ["Dynamic", "Harmony", "StaffText", "TempoText", "RehearsalMark"]; all when omitted
        """
        params = _range(start_tick, end_tick, staff, None)
        if kinds:
            params["kinds"] = kinds
        return await client.send_command("removeAnnotations", params)

    @mcp.tool()
    async def save_score(path: Optional[str] = None, ext: Optional[str] = None):
        """Save the open score in place (Ctrl+S) when called without arguments, or export it to `path`
        (pdf, musicxml, mxl, mid, png, svg ...) when a path is given. mscz export is refused: the 4.7.5
        plugin API cannot write it (only the in-place save can)."""
        params = {}
        if path:
            params["path"] = path
        if ext:
            params["ext"] = ext
        return await client.send_command("saveScore", params)
