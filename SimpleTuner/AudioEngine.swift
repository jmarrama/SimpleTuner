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
    @Published var isRunning: Bool = false
    @Published var errorMessage: String?
    
    // Device status
    private var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
    
    init() {
        audioEngine = AVAudioEngine()
        inputNode = audioEngine.inputNode
        setupAudioSession()
    }
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            
            // Request microphone permission first
            try AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async {
                    if !granted {
                        self.handleError(AudioEngineError.noInputAvailable)
                    }
                }
            }
            
            // Check if we have audio input available
            guard session.availableInputs?.isEmpty == false else {
                throw AudioEngineError.noInputAvailable
            }
            
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Only set these if we successfully activated the session
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
            
        } catch let error as AudioEngineError {
            handleError(error)
        } catch {
            handleError(.setupFailed(error))
        }
    }
    
    private func setupEngine() throws {
        // Check if we're in simulator and handle appropriately
        guard !isSimulator else {
            throw AudioEngineError.simulatorUnsupported
        }
        
        do {
            // Ensure the engine is stopped before configuring
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            guard let inputFormat = try? inputNode.inputFormat(forBus: 0) else {
                throw AudioEngineError.invalidFormat
            }
            
            let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: sampleRate,
                                               channels: 1,
                                               interleaved: false)!
            
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                self.processAudioBuffer(buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            isRunning = true
            errorMessage = nil
            
        } catch {
            throw AudioEngineError.setupFailed(error)
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
        for i in 0..<min(Int(buffer.frameLength), fftSize) {
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
        do {
            try setupEngine()
        } catch {
            handleError(error as? AudioEngineError ?? .setupFailed(error))
        }
    }
    
    func stop() {
        audioEngine.stop()
        inputNode.removeTap(onBus: 0)
        isRunning = false
    }
    
    private func handleError(_ error: AudioEngineError) {
        DispatchQueue.main.async { [weak self] in
            self?.isRunning = false
            self?.errorMessage = error.localizedDescription
        }
    }
}

// Custom error enum for better error handling
enum AudioEngineError: LocalizedError {
    case simulatorUnsupported
    case noInputAvailable
    case invalidFormat
    case setupFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .simulatorUnsupported:
            return "Audio input is not supported in the iOS Simulator. Please test on a physical device."
        case .noInputAvailable:
            return "No audio input device available. Please check microphone permissions."
        case .invalidFormat:
            return "Failed to get valid audio format from input device."
        case .setupFailed(let error):
            return "Audio engine setup failed: \(error.localizedDescription)"
        }
    }
}
