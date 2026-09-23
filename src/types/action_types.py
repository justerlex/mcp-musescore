"""TypedDict definitions for MuseScore MCP action sequences."""

from typing import Dict, Any, List, Literal, NotRequired
from typing_extensions import TypedDict


class getScoreAction(TypedDict):
    action: Literal["getScore"]
    params: Dict[str, Any]


class addNoteParams(TypedDict):
    pitch: int
    duration: Dict[Literal["numerator", "denominator"], int]
    advanceCursorAfterAction: bool
    addToChord: NotRequired[bool]


class addNoteAction(TypedDict):
    action: Literal["addNote"]
    params: addNoteParams


class addRestParams(TypedDict):
    duration: Dict[Literal["numerator", "denominator"], int]
    advanceCursorAfterAction: bool


class addRestAction(TypedDict):
    action: Literal["addRest"]
    params: addRestParams


class addTupletParams(TypedDict):
    duration: Dict[Literal["numerator", "denominator"], int]
    ratio: Dict[Literal["numerator", "denominator"], int]
    advanceCursorAfterAction: bool


class addTupletAction(TypedDict):
    action: Literal["addTuplet"]
    params: addTupletParams


class addLyricsParams(TypedDict):
    lyrics: List[str]
    verse: int


class addLyricsAction(TypedDict):
    action: Literal["addLyrics"]
    params: addLyricsParams


class addInstrumentParams(TypedDict):
    instrumentId: str


class addInstrumentAction(TypedDict):
    action: Literal["addInstrument"]
    params: addInstrumentParams


class setStaffMuteParams(TypedDict):
    staff: int
    mute: bool


class setStaffMuteAction(TypedDict):
    action: Literal["setStaffMute"]
    params: setStaffMuteParams


class setInstrumentSoundParams(TypedDict):
    staff: int
    instrumentId: str


class setInstrumentSoundAction(TypedDict):
    action: Literal["setInstrumentSound"]
    params: setInstrumentSoundParams


class appendMeasureAction(TypedDict):
    action: Literal["appendMeasure"]
    params: Dict[str, Any]


class deleteSelectionAction(TypedDict):
    action: Literal["deleteSelection"]
    params: Dict[str, Any]


class getCursorInfoAction(TypedDict):
    action: Literal["getCursorInfo"]
    params: Dict[str, Any]


class goToMeasureParams(TypedDict):
    measure: int


class goToMeasureAction(TypedDict):
    action: Literal["goToMeasure"]
    params: goToMeasureParams


class nextElementAction(TypedDict):
    action: Literal["nextElement"]
    params: Dict[str, Any]


class prevElementAction(TypedDict):
    action: Literal["prevElement"]
    params: Dict[str, Any]


class selectCurrentMeasureAction(TypedDict):
    action: Literal["selectCurrentMeasure"]
    params: Dict[str, Any]


class insertMeasureAction(TypedDict):
    action: Literal["insertMeasure"]
    params: Dict[str, Any]


class goToFinalMeasureAction(TypedDict):
    action: Literal["goToFinalMeasure"]
    params: Dict[str, Any]


class goToBeginningOfScoreAction(TypedDict):
    action: Literal["goToBeginningOfScore"]
    params: Dict[str, Any]


class setTimeSignatureParams(TypedDict):
    numerator: int
    denominator: int


class setTimeSignatureAction(TypedDict):
    action: Literal["setTimeSignature"]
    params: setTimeSignatureParams


class undoAction(TypedDict):
    action: Literal["undo"]
    params: Dict[str, Any]


class nextStaffAction(TypedDict):
    action: Literal["nextStaff"]
    params: Dict[str, Any]


class prevStaffAction(TypedDict):
    action: Literal["prevStaff"]
    params: Dict[str, Any]


# Notation extensions (23-Sep-2026): params as in the matching tool, camelCase keys


class getSelectionAction(TypedDict):
    action: Literal["getSelection"]
    params: Dict[str, Any]


class getMeasuresAction(TypedDict):
    action: Literal["getMeasures"]
    params: Dict[str, Any]


class addAnnotationAction(TypedDict):
    action: Literal["addAnnotation"]
    params: Dict[str, Any]


class setKeySignatureAction(TypedDict):
    action: Literal["setKeySignature"]
    params: Dict[str, Any]


class addArticulationAction(TypedDict):
    action: Literal["addArticulation"]
    params: Dict[str, Any]


class addTieAction(TypedDict):
    action: Literal["addTie"]
    params: Dict[str, Any]


class addSlurAction(TypedDict):
    action: Literal["addSlur"]
    params: Dict[str, Any]


class addHairpinAction(TypedDict):
    action: Literal["addHairpin"]
    params: Dict[str, Any]


class addOttavaAction(TypedDict):
    action: Literal["addOttava"]
    params: Dict[str, Any]


class transposeAction(TypedDict):
    action: Literal["transpose"]
    params: Dict[str, Any]


class setDurationAction(TypedDict):
    action: Literal["setDuration"]
    params: Dict[str, Any]


class saveScoreAction(TypedDict):
    action: Literal["saveScore"]
    params: Dict[str, Any]


class removeAnnotationsAction(TypedDict):
    action: Literal["removeAnnotations"]
    params: Dict[str, Any]


class setTempoAction(TypedDict):
    action: Literal["setTempo"]
    params: Dict[str, Any]


class selectCustomRangeAction(TypedDict):
    action: Literal["selectCustomRange"]
    params: Dict[str, Any]


ActionSequence = List[
    getScoreAction | addNoteAction | addRestAction | addTupletAction | 
    addLyricsAction | addInstrumentAction | setStaffMuteAction | 
    setInstrumentSoundAction | appendMeasureAction | deleteSelectionAction | 
    getCursorInfoAction | goToMeasureAction | nextElementAction | 
    prevElementAction | selectCurrentMeasureAction | insertMeasureAction | 
    goToFinalMeasureAction | goToBeginningOfScoreAction | setTimeSignatureAction | 
    undoAction | nextStaffAction | prevStaffAction |
    getSelectionAction | getMeasuresAction | addAnnotationAction | setKeySignatureAction | addArticulationAction | addTieAction | addSlurAction | addHairpinAction | addOttavaAction | transposeAction | setDurationAction | saveScoreAction | removeAnnotationsAction | setTempoAction | selectCustomRangeAction
]