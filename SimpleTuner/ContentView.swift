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
            Text("\(String(format: "%.1f", audioEngine.currentFrequency)) Hz")
                .font(.system(size: 50, weight: .light, design: .rounded))
            
            Text(audioEngine.closestNote.name)
                .font(.system(size: 70, weight: .regular, design: .rounded))
            
            TunerGauge(cents: audioEngine.cents)
                .frame(height: 200)
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
