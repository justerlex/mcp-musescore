import QtQuick 2.9
import MuseScore 3.0

MuseScore {
    id: root
    menuPath: "Plugins.MuseScore API Server"
    description: "Exposes MuseScore API via WebSocket (Clean Version)"
    version: "2.0"
    
    property var clientConnections: []
    property var selectionState: ({
        startStaff: 0,
        endStaff: 1,
        startTick: 0,
        elements: []
    })

    // ========================================
    // WEBSOCKET & MESSAGE PROCESSING
    // ========================================

    function processMessage(message, clientId) {
        console.log("Received message: " + message);
        try {
            var command = JSON.parse(message);
            var result = processCommand(command);
            api.websocketserver.send(clientId, JSON.stringify({
                status: "success",
                result: result
            }));
        } catch (e) {
            console.log("Error processing command: " + e.toString());
            api.websocketserver.send(clientId, JSON.stringify({
                status: "error",
                message: e.toString()
            }));
        }
    }

    function processCommand(command) {
        var result = dispatchCommand(command);
        if (result && result.success && !result.error && isWriteAction(command.action)) {
            result.currentSelection = freshState();
        }
        return result;
    }

    function dispatchCommand(command) {
        console.log("Processing command: " + command.action);
        
        switch(command.action) {
            // Core operations
            case "getScore":                return getScore(command.params);
            case "syncStateToSelection":    return syncStateToSelection();
            case "ping":                    return "pong";
            case "undo":                    return undo();
            case "goToBeginningOfScore":    return goToBeginningOfScore();
            case "processSequence":         return processSequence(command.params);

            // Navigation
            case "getCursorInfo":           return getCursorInfo(command.params);
            case "goToMeasure":             return goToMeasure(command.params);
            case "goToFinalMeasure":        return goToFinalMeasure(command.params);
            case "nextElement":             return nextElement(command.params);
            case "prevElement":             return prevElement(command.params);
            case "nextStaff":               return nextStaff(command.params);
            case "prevStaff":               return prevStaff(command.params);

            // Selection
            case "selectCurrentMeasure":    return selectCurrentMeasure(command.params);
            case "selectCustomRange":       return selectCustomRange(command.params);

            // Notes & Music
            case "addNote":                 return addNote(command.params);
            case "addRest":                 return addRest(command.params);
            case "addTuplet":               return addTuplet(command.params);
            case "addLyrics":               return addLyrics(command.params);

            // Measures
            case "appendMeasure":           return appendMeasure(command.params);
            case "insertMeasure":           return insertMeasure(command.params);
            case "deleteSelection":         return deleteSelection(command.params);

            // Staff & Instruments
            case "addInstrument":           return addInstrument(command.params);
            case "setStaffMute":            return setStaffMute(command.params);
            case "setInstrumentSound":      return setInstrumentSound(command.params);
            case "setTimeSignature":        return setTimeSignature(command.params);
            case "setTempo":                return setTempo(command.params);

            // Notation extensions (23-Sep-2026)
            case "getSelection":            return getSelection(command.params);
            case "getMeasures":             return getMeasures(command.params);
            case "addAnnotation":           return addAnnotation(command.params);
            case "setKeySignature":         return setKeySignature(command.params);
            case "addArticulation":         return addArticulation(command.params);
            case "addTie":                  return addTie(command.params);
            case "addSlur":                 return addSlur(command.params);
            case "addHairpin":              return addHairpin(command.params);
            case "addOttava":               return addOttava(command.params);
            case "transpose":               return transpose(command.params);
            case "setDuration":             return setDuration(command.params);
            case "saveScore":               return saveScore(command.params);
            case "removeAnnotations":       return removeAnnotations(command.params);

            default:
                throw new Error("Unknown command: " + command.action);
        }
    }

    // ========================================
    // UTILITY FUNCTIONS
    // ========================================

    function validateParams(params, required) {
        var missing = [];
        for (var i = 0; i < required.length; i++) {
            if (params[required[i]] === undefined) {
                missing.push(required[i]);
            }
        }
        return missing.length > 0 ? { error: "Missing required parameters: " + missing.join(", ") } : { valid: true };
    }

    function executeWithUndo(operation) {
        if (!curScore) return { error: "No score open" };
        
        curScore.startCmd();
        try {
            var result = operation();
            curScore.endCmd();
            return result;
        } catch (e) {
            curScore.endCmd(true);
            return { error: e.toString() };
        }
    }

    function getNoteName(note) {
        const noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"];
        return noteNames[note % 12];
    }

    function getTpcName(tpc) {
        if (tpc === -1) return "Fbb";
        var tpcNames = [
            "Cbb", "Gbb", "Dbb", "Abb", "Ebb", "Bbb", "Fb",
            "Cb",  "Gb",  "Db",  "Ab",  "Eb",  "Bb",  "F",
            "C",   "G",   "D",   "A",   "E",   "B",   "F#",
            "C#",  "G#",  "D#",  "A#",  "E#",  "B#",  "F##",
            "C##", "G##", "D##", "A##", "E##", "B##", "F###"
        ];
        if (tpc >= 0 && tpc < tpcNames.length) {
            return tpcNames[tpc];
        }
        return "Unknown";
    }

    function getDurationName(duration) {
        const durationNames = ["LONG","BREVE","WHOLE","HALF","QUARTER","EIGHTH","16TH","32ND","64TH","128TH","256TH","512TH","1024TH","ZERO","MEASURE","INVALID"];
        return durationNames[duration] || "UNKNOWN";
    }

    // ========================================
    // CURSOR MANAGEMENT
    // ========================================

    function createCursor(params) {
        if (!curScore) throw new Error("No score open");
        
        if (!params || Object.keys(params).length === 0) {
            params = selectionState;
        }
        
        var cursor = curScore.newCursor();
        cursor.inputStateMode = Cursor.INPUT_STATE_SYNC_WITH_SCORE;
        
        // Set track
        if (params.startStaff !== undefined) cursor.staffIdx = params.startStaff;
        
        // Position cursor
        if (params.rewindMode !== undefined) {
            cursor.rewind(params.rewindMode);
        } else if (params.startTick !== undefined) {
            try {
                cursor.rewindToTick(params.startTick);
            } catch (e) {
                console.log("rewindToTick failed, using manual navigation");
                cursor.rewind(0);
                while (cursor.tick < params.startTick && cursor.next()) {}
            }
        } else if (params.measure !== undefined) {
            cursor.rewind(0);
            for (var i = 0; i < params.measure && cursor.nextMeasure(); i++) {}
        } else {
            cursor.rewind(0);
        }
        
        // INPUT_STATE_SYNC_WITH_SCORE makes a new cursor inherit the score's last input voice; a voice-1 entry then
        // scrambles every later walk (getScore skipped bars without voice-1 content, 23-Sep-2026). Voice 0 unless asked.
        // Set AFTER positioning: a voice-1 addNote before this move reported success and wrote nothing (MS 4.7.5).
        cursor.voice = (params.voice !== undefined) ? params.voice : 0;

        // Set duration
        if (params.duration) {
            cursor.setDuration(params.duration.numerator || 1, params.duration.denominator || 4);
        }
        
        return cursor;
    }

    function initCursorState() {
        if (!curScore) return "No score open";
        
        return executeWithUndo(function() {
            var cursor = curScore.newCursor();
            cursor.rewind(0);

            var startTick = cursor.tick;
            cursor.next();
            var endTick = cursor.tick;
            var element = cursor.element;

            selectionState = {
                startStaff: cursor.staffIdx,
                endStaff: cursor.staffIdx + 1,
                startTick: startTick,
                elements: element ? [processElement(element)] : []
            };
            
            curScore.selection.clear();
            curScore.selection.selectRange(startTick, endTick, 0, 0);
            
            return "Initialized at " + [startTick, endTick, 0, 0].join(',');
        });
    }

    // ========================================
    // ELEMENT PROCESSING
    // ========================================

    function processElement(element) {
        if (!element) return null;
        if (element.name !== "Chord" && element.name !== "Rest") return null;

        var base = {
            name: element.name,
            durationTicks: element.actualDuration ? element.actualDuration.ticks : 0,
            isTie: element.tieForward ? true : false,
            isTuplet: element.tuplet ? true : false
        };

        if (element.lyrics && element.lyrics.length > 0) {
            base.lyrics = [];
            for (var l = 0; l < element.lyrics.length; l++) {
                var lyr = element.lyrics[l];
                if (lyr) {
                    base.lyrics.push({
                        text: lyr.text,
                        no: lyr.no,
                        syllabic: lyr.syllabic
                    });
                }
            }
        }

        if (element.name === "Chord") {
            base.notes = [];
            var notesObj = element.notes || {};
            var keys = Object.keys(notesObj);
            for (var k = 0; k < keys.length; k++) {
                var note = notesObj[keys[k]];
                base.notes.push({
                    pitchMidi: note.pitch,
                    tpc: note.tpc,
                    pitchName: getTpcName(note.tpc)
                });
            }
        }
                
        return base;
    }

    // ========================================
    // CORE OPERATIONS
    // ========================================

    function undo() {
        if (!curScore) return { error: "No score open" };
        // 4.7+ registers undo under its URI code; a bare "undo" is "not a registered action" there. Older
        // versions know only the bare name. Outside startCmd/endCmd by nature (an undo inside a command is nonsense).
        var uriActions = mscoreMajorVersion > 4 || (mscoreMajorVersion === 4 && mscoreMinorVersion >= 7);
        cmd(uriActions ? "action://notation/undo" : "undo");
        return { success: true, message: "Undo successful" };
    }

    function goToBeginningOfScore() {
        var response = initCursorState();
        return { 
            success: true, 
            message: response, 
            currentSelection: selectionState,
            currentScore: getScoreSummary()
        };
    }

    function processSequence(params) {
        if (!curScore) return { error: "No score open" };
        if (!params.sequence) return { error: "No sequence specified" };

        var validCommands = [
            "getScore", "addNote", "addRest", "addTuplet", "appendMeasure", "deleteSelection",
            "getCursorInfo", "goToMeasure", "nextElement", "prevElement", "nextStaff", "prevStaff",
            "selectCurrentMeasure", "processSequence", "insertMeasure", "goToFinalMeasure",
            "goToBeginningOfScore", "setTimeSignature", "addLyrics", "addInstrument",    
            "setStaffMute", "setInstrumentSound", "setTempo", "undo", "selectCustomRange",
            "getSelection", "getMeasures", "addAnnotation", "setKeySignature", "addArticulation", "addTie",
            "addSlur", "addHairpin", "addOttava", "transpose", "setDuration", "saveScore", "removeAnnotations"
        ];

        try {
            for (var i = 0; i < params.sequence.length; i++) {
                var command = params.sequence[i];
                if (!validCommands.includes(command.action)) {
                    throw new Error("Invalid command: " + command.action);
                }
                processCommand(command);
            }
            return { success: true, message: "Sequence processed", currentSelection: selectionState };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    // ========================================
    // NAVIGATION FUNCTIONS
    // ========================================

    function syncStateToSelection() {
        if (!curScore) return { error: "No score open" };

        try {
            var selection = curScore.selection;
            var startSegment = selection.startSegment;
            var endSegment = selection.endSegment;

            if (startSegment && endSegment) {
                var cursor = createCursor({
                    startTick: startSegment.tick,
                    startStaff: selection.startStaff    
                });

                var elementsMap = {};
                for (var st = selection.startStaff; st < selection.endStaff; st++) {
                    elementsMap[`staff${st}`] = [];
                }

                var currentSegment = startSegment;
                while (currentSegment && currentSegment.tick < endSegment.tick) {
                    for (var s = selection.startStaff; s < selection.endStaff; s++) {
                        for (var v = 0; v < 4; v++) {
                            var track = s * 4 + v;
                            var el = currentSegment.elementAt(track);
                            if (el) {
                                var processed = processElement(el);
                                if (processed) {
                                    processed.voice = v;
                                    processed.startTick = currentSegment.tick;
                                    elementsMap[`staff${s}`].push(processed);
                                }
                            }
                        }
                    }
                    currentSegment = currentSegment.next;
                }

                selectionState = {
                    startStaff: selection.startStaff,
                    endStaff: selection.endStaff,
                    startTick: startSegment.tick,
                    elements: elementsMap,
                    totalDuration: endSegment.tick - startSegment.tick
                };
            } else {
                var c = createCursor();
                if (c && c.element) {
                    var elElement = processElement(c.element);
                    elElement.startTick = c.tick;
                    var sStart = selection.startStaff || 0;
                    var singleMap = {};
                    singleMap[`staff${sStart}`] = [elElement];
                    
                    selectionState = {
                        startStaff: sStart,
                        endStaff: sStart + 1,
                        startTick: c.tick,
                        elements: singleMap,
                        totalDuration: elElement.durationTicks
                    };
                } else {
                    return { error: "No valid selection or cursor elements found" };
                }
            }

            return { success: true, currentSelection: selectionState };
        } catch (e) {
            return { success: false, error: e.toString() };
        }
    }

    function getCursorInfo(params) {
        if (!curScore) return { error: "No score open" };
        
        syncStateToSelection();
        return { 
            success: true, 
            currentSelection: selectionState, 
            currentScore: params && params.verbose !== "false" ? getScoreSummary() : null
        };
    }

    function goToMeasure(params) {
        var validation = validateParams(params, ["measure"]);
        if (!validation.valid) return validation;

        return executeWithUndo(function() {
            var score = getScoreSummary();
            if (params.measure < 1 || params.measure > score.measures.length) {
                return { error: "Invalid measure number" };
            }
            var measureIdx = params.measure - 1;
            var measure = score.measures[measureIdx];
            var startTick = measure.startTick;
            
            var endTick = (measureIdx + 1 < score.measures.length) ? score.measures[measureIdx + 1].startTick : curScore.lastSegment.tick;
            
            curScore.selection.clear();
            curScore.selection.selectRange(startTick, endTick, 0, curScore.nstaves);
            
            var res = syncStateToSelection();
            if (res.error) return res;
            
            return { success: true, currentSelection: selectionState };
        });
    }

    function nextElement(params) {
        return executeWithUndo(function() {
            syncStateToSelection();
            
            var cursor = createCursor({ 
                startTick: selectionState.startTick, 
                startStaff: selectionState.startStaff 
            });

            var numElements = params && params.numElements || 1;
            var success = true;
            for (var i = 0; i < numElements && success; i++) {
                success = cursor.next();
            }
            
            if (success) {
                var element = processElement(cursor.element);
                var startTick = cursor.tick;
                var staffIdx = cursor.staffIdx;
                
                // Check if we need to append a measure
                if (startTick + element.durationTicks >= curScore.lastSegment.tick) {
                    cmd("append-measure");
                }

                curScore.selection.clear();
                curScore.selection.selectRange(startTick, startTick + element.durationTicks, staffIdx, staffIdx + 1);

                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx + 1,
                    startTick: startTick,
                    elements: [element],
                    totalDuration: element.durationTicks
                };
                
                return { success: true, currentSelection: selectionState };
            } else {
                return { success: false, message: "End of score reached" };
            }
        });
    }

    function prevElement(params) {
        return executeWithUndo(function() {
            syncStateToSelection();
            
            var cursor = createCursor({ 
                startTick: selectionState.startTick, 
                startStaff: selectionState.startStaff 
            });

            var endTick = cursor.tick;
            var numElements = params && params.numElements || 1;
            var success = true;
            
            for (var i = 0; i < numElements && success; i++) {
                success = cursor.prev();
            }

            if (success) {
                var element = processElement(cursor.element);
                var startTick = cursor.tick;
                var staffIdx = cursor.staffIdx;
                
                curScore.selection.clear();
                curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx + 1);

                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx + 1,
                    startTick: startTick,
                    elements: [element],
                    totalDuration: endTick - startTick
                };
                
                return { success: true, currentSelection: selectionState };
            } else {
                return { success: false, message: "Beginning of score reached" };
            }
        });
    }

    function nextStaff(params) {
        return executeWithUndo(function() {
            syncStateToSelection();

            if (selectionState.endStaff >= curScore.nstaves) {
                return { success: false, message: "Already at last staff" };
            }

            var newStaff = selectionState.endStaff;
            var cursor = createCursor({ 
                startTick: selectionState.startTick, 
                startStaff: newStaff 
            });

            var element = processElement(cursor.element);
            
            curScore.selection.clear();
            curScore.selection.selectRange(
                selectionState.startTick, 
                selectionState.startTick + element.durationTicks, 
                newStaff, 
                newStaff + 1
            );

            selectionState = {
                startStaff: newStaff,
                endStaff: newStaff + 1,
                startTick: selectionState.startTick,
                elements: [element],
                totalDuration: element.durationTicks
            };

            return { success: true, currentSelection: selectionState };
        });
    }

    function prevStaff(params) {
        return executeWithUndo(function() {
            syncStateToSelection();

            if (selectionState.startStaff <= 0) {
                return { success: false, message: "Already at first staff" };
            }

            var newStaff = selectionState.startStaff - 1;
            var cursor = createCursor({ 
                startTick: selectionState.startTick, 
                startStaff: newStaff 
            });

            var element = processElement(cursor.element);
            
            curScore.selection.clear();
            curScore.selection.selectRange(
                selectionState.startTick, 
                selectionState.startTick + element.durationTicks, 
                newStaff, 
                newStaff + 1
            );

            selectionState = {
                startStaff: newStaff,
                endStaff: newStaff + 1,
                startTick: selectionState.startTick,
                elements: [element],
                totalDuration: element.durationTicks
            };

            return { success: true, currentSelection: selectionState };
        });
    }

    function goToFinalMeasure(params) {
        return executeWithUndo(function() {
            var cursor = createCursor({ startTick: 0 });
            var count = 0;
            var startTick = 0;

            while (cursor.nextMeasure()) {
                startTick = cursor.tick;
                count++;
            }

            if (count === 0) {
                return { success: false, message: "Already at the last measure" };
            }

            cursor.rewindToTick(startTick);
            cursor.next();
            var endTick = cursor.tick;
            var staffIdx = cursor.staffIdx;
            
            curScore.selection.clear();
            curScore.selection.selectRange(startTick, endTick, staffIdx, staffIdx + 1);
            
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx + 1,
                startTick: startTick,
                elements: [processElement(cursor.element)],
                totalDuration: endTick - startTick
            };

            return { success: true, currentSelection: selectionState };
        });
    }

    // ========================================
    // SELECTION FUNCTIONS
    // ========================================

    function selectCurrentMeasure() {
        return executeWithUndo(function() {
            var cursor = createCursor({ 
                startTick: selectionState.startTick || 0, 
                startStaff: selectionState.startStaff || 0 
            });

            var currTick = cursor.tick;
            var scoreSummary = getScoreSummary();

            var measureIdx = scoreSummary.measures.filter(function(m) { 
                return m.startTick <= currTick; 
            }).length - 1;
            
            if (measureIdx < 0) return { error: "Invalid cursor position" };
            
            var measure = scoreSummary.measures[measureIdx];
            var startTick = measure.startTick;
            var endTick = (measureIdx + 1 < scoreSummary.measures.length) ? scoreSummary.measures[measureIdx + 1].startTick : curScore.lastSegment.tick;

            curScore.selection.clear();
            curScore.selection.selectRange(startTick, endTick, 0, curScore.nstaves);

            var res = syncStateToSelection();
            if (res.error) return res;
            
            return { success: true, message: `Selected measure ${measureIdx + 1}`, currentSelection: selectionState };
        });
    }

    function selectCustomRange(params) {
        var validation = validateParams(params, ["startTick", "endTick", "startStaff", "endStaff"]);
        if (!validation.valid) return validation;

        return executeWithUndo(function() {
            var startTick = params.startTick;
            var endTick = params.endTick;
            var startStaff = params.startStaff;
            var endStaff = params.endStaff;

            // Visual GUI snap
            curScore.selection.clear();
            curScore.selection.selectRange(startTick, endTick, startStaff, endStaff);

            var elementsMap = {};
            for (var st = startStaff; st < endStaff; st++) {   // endStaff exclusive, as MuseScore's selectRange
                elementsMap[`staff${st}`] = [];
            }

            var c = createCursor({ startTick: 0, startStaff: startStaff });
            c.rewind(0);
            var currentSegment = c.segment;

            while (currentSegment && currentSegment.tick < startTick) {
                currentSegment = currentSegment.next;
            }

            while (currentSegment && currentSegment.tick < endTick) {
                for (var s = startStaff; s < endStaff; s++) {
                    for (var v = 0; v < 4; v++) {
                        var track = s * 4 + v;
                        var el = currentSegment.elementAt(track);
                        if (el) {
                            var processed = processElement(el);
                            if (processed) {
                                processed.voice = v;
                                processed.startTick = currentSegment.tick;
                                elementsMap[`staff${s}`].push(processed);
                            }
                        }
                    }
                }
                currentSegment = currentSegment.next;
            }

            selectionState = {
                startStaff: startStaff,
                endStaff: endStaff,
                startTick: startTick,
                elements: elementsMap,
                totalDuration: endTick - startTick
            };

            return { success: true, message: "Custom range mapped", currentSelection: selectionState };
        });
    }

    // ========================================
    // NOTE & MUSIC OPERATIONS
    // ========================================

    function addNote(params) {
        var validation = validateParams(params, ["pitch", "duration", "advanceCursorAfterAction"]);
        if (!validation.valid) return validation;

        if (!params.duration.numerator || !params.duration.denominator) {
            return { error: "Duration must be specified as { numerator: int, denominator: int }" };
        }

        return executeWithUndo(function() {
            syncStateToSelection();
            
            var cursor = createCursor(params.voice !== undefined ? Object.assign({}, selectionState, { voice: params.voice }) : undefined);
            cursor.setDuration(params.duration.numerator, params.duration.denominator);

            // Melody is the default. Pass addToChord: true to stack a pitch on the current chord.
            cursor.addNote(params.pitch, params.addToChord === true);
            cursor.rewindToTick(selectionState.startTick);

            if (params.advanceCursorAfterAction) {
                cursor.next();
            }

            var element = processElement(cursor.element);
            var startTick = cursor.tick;
            var staffIdx = cursor.staffIdx;
            var durationTicks = element && element.durationTicks ? element.durationTicks : 0;

            curScore.selection.clear();
            if (durationTicks > 0) {
                curScore.selection.selectRange(startTick, startTick + durationTicks, staffIdx, staffIdx + 1);
            }

            var syncRes = syncStateToSelection();
            if (syncRes && syncRes.error) {
                var staffMap = {};
                staffMap["staff" + staffIdx] = element ? [element] : [];
                selectionState = {
                    startStaff: staffIdx,
                    endStaff: staffIdx + 1,
                    startTick: startTick,
                    elements: staffMap,
                    totalDuration: durationTicks
                };
            }

            return { 
                success: true, 
                message: "Note added with pitch " + params.pitch,
                currentSelection: selectionState
            };
        });
    }

    function addRest(params) {
        var validation = validateParams(params, ["duration", "advanceCursorAfterAction"]);
        if (!validation.valid) return validation;

        if (!params.duration.numerator || !params.duration.denominator) {
            return { error: "Duration must be specified as { numerator: int, denominator: int }" };
        }

        return executeWithUndo(function() {
            syncStateToSelection();
            
            var cursor = createCursor(params.voice !== undefined ? Object.assign({}, selectionState, { voice: params.voice }) : undefined);
            cursor.setDuration(params.duration.numerator, params.duration.denominator);
            cursor.addRest();
            cursor.rewindToTick(selectionState.startTick);

            if (params.advanceCursorAfterAction) {
                cursor.next();
            }

            var element = processElement(cursor.element);
            var startTick = cursor.tick;
            var staffIdx = cursor.staffIdx;

            curScore.selection.clear();
            curScore.selection.selectRange(startTick, startTick + element.durationTicks, staffIdx, staffIdx + 1);

            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx + 1,
                startTick: startTick,
                elements: [element],
                totalDuration: element.durationTicks
            };

            return { success: true, message: "Rest added", currentSelection: selectionState };
        });
    }

    function addTuplet(params) {
        var validation = validateParams(params, ["ratio", "duration", "advanceCursorAfterAction"]);
        if (!validation.valid) return validation;

        if (!params.ratio.numerator || !params.ratio.denominator || 
            !params.duration.numerator || !params.duration.denominator) {
            return { error: "Ratio and duration must be specified as { numerator: int, denominator: int }" };
        }
        
        return executeWithUndo(function() {
            var cursor = createCursor();
            cursor.setDuration(params.duration.numerator, params.duration.denominator);
            
            var ratio = fraction(params.ratio.numerator, params.ratio.denominator);
            var duration = fraction(params.duration.numerator, params.duration.denominator);
            
            cursor.addTuplet(ratio, duration);
            cursor.next();

            if (params.advanceCursorAfterAction) {
                cursor.next();
            }

            var element = processElement(cursor.element);
            var startTick = cursor.tick;
            var staffIdx = cursor.staffIdx;

            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx + 1,
                startTick: startTick,
                elements: [element],
                totalDuration: element.durationTicks
            };

            return { 
                success: true, 
                message: "Tuplet " + params.ratio.numerator + ":" + params.ratio.denominator + " added",
                currentSelection: selectionState
            };
        });
    }

    function addLyrics(params) {
        if (!params.lyrics || !Array.isArray(params.lyrics) || params.lyrics.length === 0) {
            return { error: "Lyrics must be specified as an array of strings" };
        }
        
        return executeWithUndo(function() {
            syncStateToSelection();
            
            var cursor = createCursor({ 
                startTick: selectionState.startTick, 
                startStaff: selectionState.startStaff 
            });
            
            var lyricsArray = params.lyrics.slice();
            var verse = params.verse || 0;
            var addedCount = 0;
            var skippedCount = 0;
            
            while (cursor.element && lyricsArray.length > 0) {
                var element = cursor.element;
                
                if (element.type === Element.CHORD || element.name === "Chord") {
                    var lyr = newElement(Element.LYRICS);
                    lyr.text = lyricsArray.shift();
                    lyr.verse = verse;
                    
                    cursor.add(lyr);
                    addedCount++;
                } else if (element.type === Element.REST || element.name === "Rest") {
                    skippedCount++;
                }
                
                if (!cursor.next()) break;
            }
            
            var finalElement = processElement(cursor.element) || selectionState.elements[0];
            var finalTick = cursor.tick;
            var staffIdx = cursor.staffIdx;
            
            selectionState = {
                startStaff: staffIdx,
                endStaff: staffIdx + 1,
                startTick: finalTick,
                elements: [finalElement],
                totalDuration: finalElement.durationTicks || selectionState.totalDuration
            };
            
            curScore.selection.clear();
            curScore.selection.selectRange(finalTick, finalTick + (finalElement.durationTicks || 0), staffIdx, staffIdx + 1);
            
            var message = `Added ${addedCount} lyrics`;
            if (skippedCount > 0) message += `, skipped ${skippedCount} rests`;
            if (lyricsArray.length > 0) message += `, ${lyricsArray.length} lyrics remaining`;
            
            return { 
                success: true, 
                message: message,
                addedCount: addedCount,
                skippedCount: skippedCount,
                remainingLyrics: lyricsArray,
                currentSelection: selectionState
            };
        });
    }

    // ========================================
    // MEASURE OPERATIONS
    // ========================================

    function appendMeasure(params) {
        return executeWithUndo(function() {
            var count = params && params.count || 1;
            
            curScore.appendMeasures(count);   // plugin API; cmd("append-measure") inside startCmd/endCmd crashed MS 4.7.5
            
            return { 
                success: true, 
                message: count + " measure(s) appended",
                currentSelection: selectionState
            };
        });
    }

    function insertMeasure(params) {
        if (!curScore) return { error: "No score open" };
        cmd("insert-measure");   // its own undo step; never inside startCmd/endCmd (MS 4.7.5 crashes)
        syncStateToSelection();
        return {
            success: true,
            message: "Measure inserted",
            currentSelection: selectionState
        };
    }

    function deleteSelection(params) {
        if (!curScore) return { error: "No score open" };
        if (params && params.startTick !== undefined && params.endTick !== undefined) {
            var staff = params.staff !== undefined ? params.staff : (selectionState.startStaff || 0);
            var endStaff = params.endStaff !== undefined ? params.endStaff : staff + 1;   // exclusive
            curScore.selection.clear();
            if (!curScore.selection.selectRange(params.startTick, params.endTick, staff, endStaff)) {
                return { error: "selectRange refused ticks " + params.startTick + "-" + params.endTick };
            }
        } else if (params && params.measure) {
            createCursor({ measure: params.measure });
        }
        cmd("delete");   // its own undo step; never inside startCmd/endCmd (MS 4.7.5 crashes)
        return {
            success: true,
            message: "Selection deleted",
            currentSelection: selectionState
        };
    }

    // ========================================
    // STAFF & INSTRUMENT OPERATIONS
    // ========================================

    function addInstrument(params) {
        var validation = validateParams(params, ["instrumentId"]);
        if (!validation.valid) return validation;
        
        return executeWithUndo(function() {
            curScore.appendPart(params.instrumentId);
            return { success: true, message: "Instrument " + params.instrumentId + " added" };
        });
    }

    function setStaffMute(params) {
        var validation = validateParams(params, ["staff"]);
        if (!validation.valid) return validation;
        
        return executeWithUndo(function() {
            var staff = curScore.staves && curScore.staves[params.staff] || 
                       (typeof curScore.staff === "function" ? curScore.staff(params.staff) : null);
            
            if (staff) {
                staff.invisible = Boolean(params.mute);
                return { success: true, message: "Staff " + (params.mute ? "muted" : "unmuted") };
            } else {
                return { error: "Staff not found" };
            }
        });
    }

    function setInstrumentSound(params) {
        var validation = validateParams(params, ["staff", "instrumentId"]);
        if (!validation.valid) return validation;
        
        return executeWithUndo(function() {
            cmd("instruments");
            return { success: true, message: "Instrument dialog opened, manual selection required" };
        });
    }

    function setTimeSignature(params) {
        var validation = validateParams(params, ["numerator", "denominator"]);
        if (!validation.valid) return validation;
        
        return executeWithUndo(function() {
            var cursor = createCursor();
            var currTick = cursor.tick;
            var currStaff = cursor.staffIdx;

            var ts = newElement(Element.TIMESIG);
            ts.timesig = fraction(params.numerator, params.denominator);
            cursor.add(ts);

            return { 
                success: true, 
                message: "Time signature set to " + params.numerator + "/" + params.denominator
            };
        });
    }

    function setTempo(params) {
        var validation = validateParams(params, ["bpm"]);
        if (!validation.valid) return validation;
        
        return executeWithUndo(function() {
            var cursor = createCursor();
            
            var tempo = newElement(Element.TEMPO_TEXT);
            tempo.tempo = params.bpm / 60.0;
            tempo.text = "♩ = " + params.bpm;
            
            cursor.add(tempo);
            
            return { success: true, message: "Tempo set to " + params.bpm + " BPM" };
        });
    }

    // ========================================
    // NOTATION EXTENSIONS (23-Sep-2026 · verified against MuseScore Studio 4.7.5 src/engraving/api/v1)
    //   Segment-attached elements (dynamics, chord symbols, texts, tempo, rehearsal marks) and key
    //   signatures go through Cursor.add(). Articulations, ties, slurs, hairpins, ottavas and
    //   transposition go through MuseScore's own actions on a range selection (each action is its
    //   own undo step, never inside startCmd/endCmd). Every write answers with a FRESH selection
    //   state (see processCommand) instead of the cached one.
    // ========================================

    function isWriteAction(action) {
        return ["addNote", "addRest", "addTuplet", "addLyrics", "appendMeasure", "insertMeasure",
                "deleteSelection", "undo", "setTimeSignature", "setTempo", "addInstrument",
                "addAnnotation", "setKeySignature", "addArticulation", "addTie", "addSlur",
                "addHairpin", "addOttava", "transpose", "setDuration", "removeAnnotations"].indexOf(action) >= 0;
    }

    // Re-read MuseScore's selection and return it (the cached selectionState is only as fresh as the last sync).
    function freshState() {
        try { syncStateToSelection(); } catch (e) { console.log("freshState: " + e); }
        return selectionState;
    }

    function getSelection(params) {
        if (!curScore) return { error: "No score open" };
        return { success: true, currentSelection: freshState() };
    }

    // A cursor at the current state's tick and staff, or at an explicit {tick, staff, voice}.
    function cursorAtState(params) {
        if (!params || params.tick === undefined) { try { syncStateToSelection(); } catch (e) {} }
        var p = { startTick: selectionState.startTick || 0, startStaff: selectionState.startStaff || 0 };
        if (params) {
            if (params.tick !== undefined) p.startTick = params.tick;
            if (params.staff !== undefined) p.startStaff = params.staff;
            if (params.voice !== undefined) p.voice = params.voice;
        }
        return createCursor(p);
    }

    function safeSubtype(el) {
        try { return el.subtypeName ? el.subtypeName() : ""; } catch (e) { return ""; }
    }

    function safeText(el) {
        try { var t = el.text; return (t === undefined || t === null) ? "" : String(t); } catch (e) { return ""; }
    }

    function safeTrack(el) {
        try { var t = el.track; return (t === undefined || t === null || t < 0) ? 0 : t; } catch (e) { return 0; }
    }

    // ---- segment-attached text-like elements ---------------------------------------------------

    function addAnnotation(params) {
        var validation = validateParams(params, ["kind", "text"]);
        if (!validation.valid) return validation;
        var kinds = {
            dynamic: Element.DYNAMIC, chordSymbol: Element.HARMONY, staffText: Element.STAFF_TEXT,
            systemText: Element.SYSTEM_TEXT, rehearsalMark: Element.REHEARSAL_MARK,
            expression: Element.EXPRESSION, tempo: Element.TEMPO_TEXT
        };
        if (kinds[params.kind] === undefined) {
            return { error: "kind must be one of: " + Object.keys(kinds).join(", ") };
        }
        return executeWithUndo(function() {
            var cursor = cursorAtState(params);
            if (!cursor.segment) throw new Error("No segment at tick " + cursor.tick);
            var el = newElement(kinds[params.kind]);
            if (params.kind === "chordSymbol") {
                // 4.7: Harmony::setProperty(TEXT) dereferences the parent (fret-diagram check), so a
                // parentless Harmony crashes MuseScore. Add it to the segment first, set the text after.
                cursor.add(el);
                el.text = String(params.text);
                return { success: true, message: "chordSymbol '" + params.text + "' at tick " + cursor.tick + ", staff " + cursor.staffIdx };
            }
            el.text = String(params.text);
            if (params.kind === "tempo") {
                var bpm = params.bpm ? parseFloat(params.bpm) : parseFloat(String(params.text).replace(/[^0-9.]/g, ""));
                if (bpm > 0) { el.tempo = bpm / 60.0; el.tempoFollowText = false; }
            }
            if (params.kind === "dynamic" && params.velocity !== undefined) el.velocity = parseInt(params.velocity);
            cursor.add(el);
            return { success: true, message: params.kind + " '" + params.text + "' at tick " + cursor.tick + ", staff " + cursor.staffIdx };
        });
    }

    // ---- key signature (fifths: -7 flats .. 0 .. 7 sharps) -------------------------------------

    function setKeySignature(params) {
        var validation = validateParams(params, ["key"]);
        if (!validation.valid) return validation;
        var key = parseInt(params.key);
        if (isNaN(key) || key < -7 || key > 7) return { error: "key is the number of fifths: -7 (Cb) .. 0 (C / Am) .. 7 (C#)" };
        return executeWithUndo(function() {
            try { syncStateToSelection(); } catch (e) {}
            var tick = params.tick !== undefined ? params.tick : (selectionState.startTick || 0);
            var staves = [];
            if (params.allStaves === false) {
                staves.push(params.staff !== undefined ? params.staff : (selectionState.startStaff || 0));
            } else {
                for (var i = 0; i < curScore.nstaves; i++) staves.push(i);
            }
            var done = [];
            for (var j = 0; j < staves.length; j++) {
                var cursor = cursorAtState({ tick: tick, staff: staves[j] });
                if (!cursor.segment) continue;
                var ks = newElement(Element.KEYSIG);
                ks.concertKey = key;
                ks.actualKey = key;
                cursor.add(ks);
                done.push(staves[j]);
            }
            return { success: true, message: "key signature " + key + " at tick " + tick + " on staves " + done.join(", ") };
        });
    }

    // ---- range actions through MuseScore's own commands ----------------------------------------

    function rangeCommand(params, code, times) {
        if (!curScore) return { error: "No score open" };
        params = params || {};
        if (params.startTick === undefined) {
            try { syncStateToSelection(); } catch (e) {}
            if (selectionState && selectionState.startTick !== undefined) {
                params.startTick = selectionState.startTick;
                params.endTick = selectionState.startTick + (selectionState.totalDuration || 240);
            }
        }
        var validation = validateParams(params, ["startTick", "endTick"]);
        if (!validation.valid) return validation;
        var staff = params.staff !== undefined ? params.staff : (selectionState.startStaff || 0);
        var endStaff = params.endStaff !== undefined ? params.endStaff : staff + 1;   // exclusive, as in MuseScore
        curScore.selection.clear();
        var ok = curScore.selection.selectRange(params.startTick, params.endTick, staff, endStaff);
        if (!ok) return { error: "selectRange refused ticks " + params.startTick + "-" + params.endTick + ", staves " + staff + ".." + (endStaff - 1) };
        var n = Math.max(1, parseInt(times || 1));
        for (var i = 0; i < n; i++) cmd(code);
        return { success: true, message: code + (n > 1 ? " x" + n : "") + " on ticks " + params.startTick + "-" + params.endTick + ", staves " + staff + ".." + (endStaff - 1) };
    }

    // A LIST selection of notes (selectRange leaves MuseScore's selected-element list empty, so add-slur
    // finds no chords and add-hairpin's "note or rest selected" gate stays shut).
    function selectNotesInRange(startTick, endTick, staff, firstLastOnly) {
        var c = curScore.newCursor();
        c.voice = 0;
        c.staffIdx = staff;
        c.rewindToTick(startTick);
        var seg = c.segment;
        var chords = [];
        while (seg && seg.tick < endTick) {
            for (var v = 0; v < 4; v++) {
                var el = seg.elementAt(staff * 4 + v);
                if (el && el.name === "Chord") chords.push(el);
            }
            seg = seg.next;
        }
        if (chords.length === 0) return 0;
        var picks = (firstLastOnly && chords.length > 1) ? [chords[0], chords[chords.length - 1]] : chords;
        curScore.selection.clear();
        var n = 0;
        for (var i = 0; i < picks.length; i++) {
            var notes = picks[i].notes;
            for (var k = 0; k < notes.length; k++) {
                curScore.selection.select(notes[k], n > 0);
                n++;
            }
        }
        return n;
    }

    function listCommand(params, code, firstLastOnly) {
        if (!curScore) return { error: "No score open" };
        params = params || {};
        if (params.startTick === undefined) {
            try { syncStateToSelection(); } catch (e) {}
            if (selectionState && selectionState.startTick !== undefined) {
                params.startTick = selectionState.startTick;
                params.endTick = selectionState.startTick + (selectionState.totalDuration || 240);
            }
        }
        var validation = validateParams(params, ["startTick", "endTick"]);
        if (!validation.valid) return validation;
        var staff = params.staff !== undefined ? params.staff : (selectionState.startStaff || 0);
        var n = selectNotesInRange(params.startTick, params.endTick, staff, firstLastOnly);
        if (!n) return { error: "no chords between ticks " + params.startTick + " and " + params.endTick + " on staff " + staff };
        cmd(code);
        return { success: true, message: code + " over " + n + " note(s), ticks " + params.startTick + "-" + params.endTick + ", staff " + staff };
    }

    function addSlur(params)    { return listCommand(params, "add-slur", true); }
    function addTie(params)     { return rangeCommand(params, "tie"); }
    function addHairpin(params) { return listCommand(params, (params && params.type === "diminuendo") ? "add-hairpin-reverse" : "add-hairpin", false); }
    function addOttava(params)  { return listCommand(params, (params && params.type === "8vb") ? "add-8vb" : "add-8va", false); }

    function addArticulation(params) {
        var codes = { staccato: "add-staccato", tenuto: "add-tenuto", marcato: "add-marcato", accent: "add-sforzato" };
        if (!params || !codes[params.type]) return { error: "type must be one of: staccato, tenuto, marcato, accent" };
        return rangeCommand(params, codes[params.type]);
    }

    function transpose(params) {
        params = params || {};
        var semis = parseInt(params.semitones || 0);
        var octs = parseInt(params.octaves || 0);
        if (!semis && !octs) return { error: "semitones and/or octaves required (signed integers)" };
        var steps = [];
        if (octs) {
            var ro = rangeCommand(params, octs > 0 ? "pitch-up-octave" : "pitch-down-octave", Math.abs(octs));
            if (!ro.success) return ro;
            steps.push(ro.message);
        }
        if (semis) {
            var rs = rangeCommand(params, semis > 0 ? "pitch-up" : "pitch-down", Math.abs(semis));
            if (!rs.success) return rs;
            steps.push(rs.message);
        }
        return { success: true, message: "transposed " + (octs ? octs + " octave(s) " : "") + (semis ? semis + " semitone(s)" : ""), steps: steps };
    }

    // ---- duration of the chord or rest at the cursor -------------------------------------------

    function setDuration(params) {
        var validation = validateParams(params, ["numerator", "denominator"]);
        if (!validation.valid) return validation;
        return executeWithUndo(function() {
            var cursor = cursorAtState(params);
            var el = cursor.element;
            if (!el || (el.name !== "Chord" && el.name !== "Rest")) {
                throw new Error("No chord or rest at tick " + cursor.tick + ", staff " + cursor.staffIdx + ", voice " + cursor.voice);
            }
            el.duration = fraction(parseInt(params.numerator), parseInt(params.denominator));
            return { success: true, message: el.name + " at tick " + cursor.tick + " is now " + params.numerator + "/" + params.denominator };
        });
    }

    // ---- save / export ---------------------------------------------------------------------------

    function saveScore(params) {
        if (!curScore) return { error: "No score open" };
        if (params && params.path) {
            var path = String(params.path);
            var ext = (params.ext ? String(params.ext) : path.split(".").pop()).toLowerCase();
            if (ext === "mscz" || ext === "mscx") {
                // 4.7.5: the plugin helper routes mscz through MscNotationWriter::writeList ("Not supported!!"),
                // leaves a 0-byte file and pops a dialog that stalls the plugin. In-place save only.
                return { error: "mscz export is not supported by the 4.7.5 plugin API; call saveScore without a path (Ctrl+S) or export to pdf / musicxml / mid / png" };
            }
            var ok = writeScore(curScore, path, ext);
            return ok ? { success: true, message: "written " + path } : { error: "writeScore refused '" + path + "' as " + ext };
        }
        cmd("file-save");
        return { success: true, message: "file-save dispatched (the same as Ctrl+S)" };
    }

    // ---- reading: a range of bars with everything in them ---------------------------------------

    function getMeasures(params) {
        if (!curScore) return { error: "No score open" };
        params = params || {};
        var total = curScore.nmeasures;
        var from = Math.max(1, parseInt(params.from || 1));
        var to = Math.min(total, parseInt(params.to || from));
        if (to < from) to = from;
        var withAnnotations = params.annotations !== false;

        var walker = curScore.newCursor();
        walker.voice = 0;
        walker.staffIdx = 0;
        walker.rewind(0);
        var ticks = [];
        for (var i = 0; i < total; i++) {
            ticks.push(walker.tick);
            if (!walker.nextMeasure()) break;
        }
        var scoreEnd = curScore.lastSegment ? curScore.lastSegment.tick + 1 : ticks[ticks.length - 1] + 1;

        var out = [];
        for (var m = from; m <= to; m++) {
            var startTick = ticks[m - 1];
            var endTick = (m < ticks.length) ? ticks[m] : scoreEnd;
            var measure = { measure: m, startTick: startTick, endTick: endTick, staves: {} };
            try { var kc = curScore.newCursor(); kc.voice = 0; kc.staffIdx = 0; kc.rewindToTick(startTick); measure.keySignature = kc.keySignature; } catch (eK) {}
            for (var s = 0; s < curScore.nstaves; s++) measure.staves["staff" + s] = { events: [], annotations: [] };

            var c = curScore.newCursor();
            c.voice = 0;
            c.staffIdx = 0;
            c.rewindToTick(startTick);
            var seg = c.segment;
            while (seg && seg.tick < endTick) {
                for (var st = 0; st < curScore.nstaves; st++) {
                    for (var v = 0; v < 4; v++) {
                        var el = seg.elementAt(st * 4 + v);
                        if (!el) continue;
                        var p = processElement(el);
                        if (!p) continue;
                        p.voice = v;
                        p.startTick = seg.tick;
                        p.offset = seg.tick - startTick;
                        if (el.name === "Chord") {
                            try {
                                var notes = el.notes;
                                for (var ni = 0; ni < p.notes.length && ni < notes.length; ni++) {
                                    p.notes[ni].tieForward = notes[ni] && notes[ni].tieForward ? true : false;
                                    p.notes[ni].tieBack = notes[ni] && notes[ni].tieBack ? true : false;
                                }
                                var arts = el.articulations;
                                if (arts && arts.length) {
                                    p.articulations = [];
                                    for (var ai = 0; ai < arts.length; ai++) if (arts[ai]) p.articulations.push(safeSubtype(arts[ai]));
                                }
                            } catch (e) { p.enrichError = e.toString(); }
                        }
                        measure.staves["staff" + st].events.push(p);
                    }
                    if (withAnnotations) {
                        var anns = seg.annotations;
                        var na = anns ? anns.length : 0;
                        for (var ai2 = 0; ai2 < na; ai2++) {
                            var an = anns[ai2];
                            if (!an) continue;
                            var tr = safeTrack(an);
                            if (Math.floor(tr / 4) !== st) continue;
                            measure.staves["staff" + st].annotations.push({
                                name: an.name, text: safeText(an), subtype: safeSubtype(an), tick: seg.tick, offset: seg.tick - startTick, voice: tr % 4
                            });
                        }
                    }
                }
                seg = seg.next;
            }
            out.push(measure);
        }

        var spans = [];
        if (withAnnotations) {
            try {
                var rangeStart = out[0].startTick, rangeEnd = out[out.length - 1].endTick;
                var sp = curScore.spanners;
                var ns = sp ? sp.length : 0;
                for (var k = 0; k < ns; k++) {
                    var x = sp[k];
                    if (!x) continue;
                    var t1 = -1, t2 = -1;
                    try { t1 = x.fraction ? x.fraction.ticks : -1; } catch (e1) {}
                    try { t2 = (x.spannerTicks && x.spannerTicks.ticks !== undefined) ? t1 + x.spannerTicks.ticks : -1; } catch (e2) {}
                    if (t2 < 0) { try { t2 = (x.endElement && x.endElement.fraction) ? x.endElement.fraction.ticks : t1; } catch (e3) { t2 = t1; } }
                    if (t1 < 0 || t1 >= rangeEnd || t2 < rangeStart) continue;
                    spans.push({ name: x.name, subtype: safeSubtype(x), tick: t1, tick2: t2, track: safeTrack(x), text: safeText(x) });
                }
            } catch (e) { spans = [{ error: e.toString() }]; }
        }
        return { success: true, from: from, to: to, numMeasures: total, measures: out, spanners: spans };
    }

    // ---- removing annotations in a range ---------------------------------------------------------

    function removeAnnotations(params) {
        var validation = validateParams(params, ["startTick", "endTick"]);
        if (!validation.valid) return validation;
        return executeWithUndo(function() {
            var staff = params.staff !== undefined ? params.staff : (selectionState.startStaff || 0);
            var kinds = (params.kinds && params.kinds.length) ? params.kinds : null;   // e.g. ["Dynamic", "Harmony", "StaffText"]
            var c = curScore.newCursor();
            c.voice = 0;
            c.staffIdx = 0;
            c.rewindToTick(params.startTick);
            var seg = c.segment;
            var removed = [];
            while (seg && seg.tick < params.endTick) {
                var anns = seg.annotations;
                var n = anns ? anns.length : 0;
                var victims = [];
                for (var i = 0; i < n; i++) {
                    var an = anns[i];
                    if (!an) continue;
                    if (Math.floor(safeTrack(an) / 4) !== staff) continue;
                    if (kinds && kinds.indexOf(an.name) < 0) continue;
                    victims.push(an);
                }
                for (var j = 0; j < victims.length; j++) {
                    removed.push({ name: victims[j].name, text: safeText(victims[j]), tick: seg.tick });
                    removeElement(victims[j]);
                }
                seg = seg.next;
            }
            return { success: true, removed: removed, message: removed.length + " annotation(s) removed" };
        });
    }

    // ========================================
    // SCORE ANALYSIS
    // ========================================

    function getScore(params) {
        if (!curScore) return { error: "No score open" };
        
        try {
            return { success: true, analysis: getScoreSummary() };
        } catch (e) {
            return { error: e.toString() };
        }
    }

    function getScoreSummary() {
        if (!curScore) return { error: "No score open" };

        return executeWithUndo(function() {
            var tempState = selectionState;
            var score = {
                title: curScore.metaTag("workTitle") || curScore.title || "",
                numMeasures: curScore.nmeasures,
                measures: [],
                staves: []
            };
            
            // Analyze staves
            for (var i = 0; i < curScore.nstaves; i++) {
                var staff = curScore.staves && curScore.staves[i] || 
                           (typeof curScore.staff === "function" ? curScore.staff(i) : null);
                
                score.staves.push({
                    name: `staff${i}`,
                    shortName: staff ? staff.shortName : "",
                    visible: staff ? !staff.invisible : true
                });
            }

            // Analyze measures
            var cursor = createCursor({startTick: 0});
            var measureBoundaries = [];

            // Get measure boundaries
            for (var i = 0; i < curScore.nmeasures; i++) {
                var measure = {
                    measure: i + 1, 
                    startTick: cursor.tick,
                    numElements: 0, 
                    elements: {}
                };

                for (var j = 0; j < curScore.nstaves; j++) {
                    measure.elements[`staff${j}`] = [];
                }

                measureBoundaries.push(cursor.tick);
                score.measures.push(measure);
                cursor.nextMeasure();
            }

            // Process elements for each staff
            for (var k = 0; k < curScore.nstaves; k++) {
                cursor.rewind(0);
                var currentSegment = cursor.segment;

                while (currentSegment) {
                    var measureIdx = measureBoundaries.filter(function(tick) {
                        return tick <= currentSegment.tick;
                    }).length - 1;

                    for (var v = 0; v < 4; v++) {
                        var track = k * 4 + v;
                        var el = currentSegment.elementAt(track);
                        if (el) {
                            score.measures[measureIdx].numElements++;
                            var processedElement = processElement(el);
                            if (processedElement) {
                                processedElement.startTick = currentSegment.tick;
                                processedElement.voice = v;
                                score.measures[measureIdx].elements[`staff${k}`].push(processedElement);
                            }
                        }
                    }
                    currentSegment = currentSegment.next;
                }
            }

            // Restore state
            selectionState = tempState;
            return score;
        });
    }

    // ========================================
    // INITIALIZATION
    // ========================================

    onRun: {
        console.log("Starting MuseScore API Server (Clean Version) on port 8790");
        
        api.websocketserver.listen(8790, function(clientId) {
            console.log("Client connected with ID: " + clientId);
            clientConnections.push(clientId);
            
            api.websocketserver.onMessage(clientId, function(message) {
                processMessage(message, clientId);
            });
        });
    
        if (curScore) {
            initCursorState();
        }
    }
}