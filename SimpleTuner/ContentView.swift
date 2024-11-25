//
//  ContentView.swift
//  SimpleTuner
//
//  Created by Joe Marrama on 11/25/24.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var audioEngine = AudioEngine()
    
    var body: some View {
        VStack(spacing: 30) {
            
            HStack(spacing: 10) {
                Text(audioEngine.closestNote.name)
                    .font(.system(size: 70, weight: .bold, design: .rounded))
                Text("(\(String(format: "%.1f", audioEngine.closestNote.frequency)) Hz)")
                    .font(.system(size: 24, weight: .regular, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .opacity(audioEngine.currentFrequency != nil ? 1 : 0.3)
            
            TunerGauge(cents: audioEngine.cents)
                .frame(height: 200)
                .opacity(audioEngine.currentFrequency != nil ? 1 : 0.3)
            
            if let frequency = audioEngine.currentFrequency {
                Text("\(String(format: "%.1f", frequency)) Hz")
                    .font(.system(size: 50, weight: .light, design: .rounded))
            } else {
                Text("Play a note")
                    .font(.system(size: 50, weight: .light, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .onAppear {
            audioEngine.start()
        }
        .onDisappear {
            audioEngine.stop()
        }
    }
}

#Preview {
    ContentView()
}
