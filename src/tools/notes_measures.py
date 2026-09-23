"""Notes and measures tools for MuseScore MCP."""

from typing import List, Optional
from ..client import MuseScoreClient


def setup_notes_measures_tools(mcp, client: MuseScoreClient):
    """Setup notes and measures tools."""
    
    @mcp.tool()
    async def add_note(pitch: int = 64, duration: dict = {"numerator": 1, "denominator": 4}, advance_cursor_after_action: bool = True, add_to_chord: bool = False, voice: Optional[int] = None):
        """Add a note at the current cursor position with the specified pitch and duration.
        
        Sequential notes write a melody. Set add_to_chord=True to stack a pitch on the current chord.
        
        Args:
            pitch: MIDI pitch value (0-127, where 60 is middle C)
            duration: Duration as {"numerator": int, "denominator": int} (e.g., {"numerator": 1, "denominator": 4} for quarter note)
            advance_cursor_after_action: Whether to move cursor to next position after adding note
            add_to_chord: If True, add this pitch to the current chord instead of writing the next melody note
        """
        return await client.send_command("addNote", {
            "pitch": pitch,
            "duration": duration,
            "advanceCursorAfterAction": advance_cursor_after_action,
            **({"voice": voice} if voice is not None else {}),
            "addToChord": add_to_chord
        })

    @mcp.tool()
    async def add_rest(duration: dict = {"numerator": 1, "denominator": 4}, advance_cursor_after_action: bool = True, voice: Optional[int] = None):
        """Add a rest at the current cursor position.
        
        Args:
            duration: Duration as {"numerator": int, "denominator": int} (e.g., {"numerator": 1, "denominator": 4} for quarter rest)
            advance_cursor_after_action: Whether to move cursor to next position after adding rest
        """
        return await client.send_command("addRest", {
            "duration": duration,
            "advanceCursorAfterAction": advance_cursor_after_action,
            **({"voice": voice} if voice is not None else {}),
        })

    @mcp.tool()
    async def add_tuplet(duration: dict = {"numerator": 1, "denominator": 4}, ratio: dict = {"numerator": 3, "denominator": 2}, advance_cursor_after_action: bool = True):
        """Add a tuplet at the current cursor position.
        
        Args:
            duration: Base duration as {"numerator": int, "denominator": int}
            ratio: Tuplet ratio as {"numerator": int, "denominator": int} (e.g., {"numerator": 3, "denominator": 2} for triplet)
            advance_cursor_after_action: Whether to move cursor to next position after adding tuplet
        """
        return await client.send_command("addTuplet", {
            "duration": duration,
            "ratio": ratio,
            "advanceCursorAfterAction": advance_cursor_after_action
        })

    @mcp.tool()
    async def add_lyrics(lyrics: List[str], verse: int = 0):
        """Add lyrics to consecutive notes starting from the current cursor position.
        
        Args:
            lyrics: List of lyric syllables to add (e.g., ["Hel", "lo", "world"])
            verse: Verse number (0-based, default is 0 for first verse)
        """
        return await client.send_command("addLyrics", {
            "lyrics": lyrics,
            "verse": verse
        })

    @mcp.tool()
    async def insert_measure():
        """Insert a measure at the current position."""
        return await client.send_command("insertMeasure")

    @mcp.tool()
    async def append_measure(count: int = 1):
        """Append measures to the end of the score."""
        return await client.send_command("appendMeasure", {"count": count})

    @mcp.tool()
    async def delete_selection(measure: Optional[int] = None, start_tick: Optional[int] = None, end_tick: Optional[int] = None,
                               staff: Optional[int] = None, end_staff: Optional[int] = None):
        """Delete the current selection, a bar, or an explicit tick range (notes become rests). end_staff exclusive."""
        params = {}
        if measure is not None:
            params["measure"] = measure
        if start_tick is not None and end_tick is not None:
            params["startTick"] = start_tick
            params["endTick"] = end_tick
            if staff is not None:
                params["staff"] = staff
            if end_staff is not None:
                params["endStaff"] = end_staff
        return await client.send_command("deleteSelection", params)

    @mcp.tool()
    async def undo():
        """Undo the last action."""
        return await client.send_command("undo")