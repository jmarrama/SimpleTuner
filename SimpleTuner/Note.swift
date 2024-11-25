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

func findClosestNote(frequency: Float?) -> (note: Note, cents: Float) {
    guard let frequency = frequency, frequency > 0 else {
        return (Note.allNotes[57], 0) // Default to A4 (440Hz)
    }
    
    // Convert to semitones relative to A4 (440 Hz)
    let semitones = 12 * log2(frequency / 440.0)
    
    // Find the closest note by rounding the semitone distance
    let roundedSemitones = round(semitones)
    let noteIndex = Int(roundedSemitones) + 57 // 57 is the index of A4 in our allNotes array
    
    // Ensure we stay within array bounds
    let boundedIndex = max(0, min(noteIndex, Note.allNotes.count - 1))
    let closestNote = Note.allNotes[boundedIndex]
    
    // Calculate cents deviation
    let cents = 100 * (semitones - roundedSemitones)
    
    return (closestNote, cents)
}
