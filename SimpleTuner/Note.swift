import Foundation

struct Note: Equatable {
    let name: String
    let frequency: Float
    
    static let allNotes: [Note] = {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var notes: [Note] = []
        
        // Generate notes from C0 (16.35 Hz) to B8 (7902.13 Hz)
        for octave in 0...8 {
            for (i, name) in noteNames.enumerated() {
                let frequency = 16.35 * pow(2, Float(octave) + Float(i) / 12.0)
                notes.append(Note(name: "\(name)\(octave)", frequency: frequency))
            }
        }
        
        return notes
    }()
}

func findClosestNote(frequency: Float) -> (note: Note, cents: Float) {
    guard frequency > 0 else { return (Note.allNotes[57], 0) } // Default to A4 (440Hz)
    
    var closestNote = Note.allNotes[0]
    var minDifference = Float.infinity
    
    for note in Note.allNotes {
        let difference = abs(frequency - note.frequency)
        if difference < minDifference {
            minDifference = difference
            closestNote = note
        }
    }
    
    // Calculate cents deviation
    let cents = 1200 * log2(frequency / closestNote.frequency)
    
    return (closestNote, cents)
}
