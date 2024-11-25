import Foundation
import AVFoundation
import Accelerate

class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var inputNode: AVAudioInputNode
    private let sampleRate: Double = 44100
    private let bufferSize: AVAudioFrameCount = 4096
    private let fftSize: Int = 4096
    
    // Published properties for UI updates
    @Published var currentFrequency: Float = 0.0
    @Published var closestNote: Note = Note(name: "A", frequency: 440.0)
    @Published var cents: Float = 0.0
    
    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        setupAudioSession()
        setupEngine()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupEngine() {
        do {
            let inputFormat = inputNode.inputFormat(forBus: 0)
            let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: sampleRate,
                                               channels: 1,
                                               interleaved: false)!
            
            // Remove any existing taps
            inputNode.removeTap(onBus: 0)
            
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                self.processAudioBuffer(buffer)
            }
            
            try audioEngine.start()
        } catch {
            print("Error setting up audio engine: \(error.localizedDescription)")
        }
    }
    
    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        
        // Create arrays for FFT input/output
        var realIn = [Float](repeating: 0, count: fftSize)
        var imagIn = [Float](repeating: 0, count: fftSize)
        var realOut = [Float](repeating: 0, count: fftSize/2)
        var imagOut = [Float](repeating: 0, count: fftSize/2)
        
        // Copy audio data to real input array
        for i in 0..<Int(buffer.frameLength) {
            realIn[i] = channelData[i]
        }
        
        // Create FFT setup
        let log2n = vDSP_Length(log2(Float(fftSize)))
        guard let fftSetup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return }
        
        // Convert real data to complex split form
        var splitComplex = DSPSplitComplex(realp: &realOut, imagp: &imagOut)
        realIn.withUnsafeMutableBufferPointer { realPtr in
            let typeConvertedPtr = UnsafeRawPointer(realPtr.baseAddress!).assumingMemoryBound(to: DSPComplex.self)
            vDSP_ctoz(typeConvertedPtr, 2, &splitComplex, 1, vDSP_Length(fftSize/2))
        }
        
        // Perform FFT
        vDSP_fft_zrip(fftSetup, &splitComplex, 1, log2n, FFTDirection(FFT_FORWARD))
        
        // Calculate magnitudes
        var magnitudes = [Float](repeating: 0, count: fftSize/2)
        vDSP_zvmags(&splitComplex, 1, &magnitudes, 1, vDSP_Length(fftSize/2))
        
        // Find peak frequency
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(magnitudes, 1, &maxMagnitude, &maxIndex, vDSP_Length(fftSize/2))
        
        let peakFrequency = Float(maxIndex) * Float(sampleRate) / Float(fftSize)
        
        // Update on main thread
        DispatchQueue.main.async { [weak self] in
            self?.updateWithFrequency(peakFrequency)
        }
        
        vDSP_destroy_fftsetup(fftSetup)
    }
    
    private func updateWithFrequency(_ frequency: Float) {
        self.currentFrequency = frequency
        let (note, cents) = findClosestNote(frequency: frequency)
        self.closestNote = note
        self.cents = cents
    }
    
    func start() {
        if !audioEngine.isRunning {
            setupAudioSession()
            setupEngine()
        }
    }
    
    func stop() {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
    }
}
