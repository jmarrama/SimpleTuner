import Foundation
import AVFoundation
import Accelerate

class AudioEngine: ObservableObject {
    private var audioEngine: AVAudioEngine
    private var inputNode: AVAudioInputNode
    
    // Get about 1hz per bin of the FFT! Also, this gets us almost up to C8!
    private let sampleRate: Double = 8192
    private let bufferSize: AVAudioFrameCount = 8192
    private let fftSize: Int = 8192
    
    // Minimum loudness to be shown in app, found based on empirical testing
    private let decibelThreshold: Float = 25

    // Calculate magnitude threshold from dB threshold
    // Since dB = 20 * log10(magnitude), then magnitude = 10^(dB/20)
    private lazy var magnitudeThreshold: Float = {
        return pow(10, decibelThreshold / 20.0)
    }()
    
    // Published properties for UI updates
    @Published var currentFrequency: Float? = nil
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
            
            // Set our lower sample rate
            try session.setPreferredSampleRate(sampleRate)  // Now 8000 Hz
            try session.setPreferredIOBufferDuration(Double(bufferSize) / sampleRate)
            
        } catch let error as AudioEngineError {
            handleError(error)
        } catch {
            handleError(.setupFailed(error))
        }
    }
    
    private func setupEngine() throws {
        guard !isSimulator else {
            throw AudioEngineError.simulatorUnsupported
        }
        
        do {
            audioEngine.stop()
            inputNode.removeTap(onBus: 0)
            
            // Get the hardware input format
            guard let hardwareFormat = try? inputNode.inputFormat(forBus: 0) else {
                throw AudioEngineError.invalidFormat
            }
            
            // Create our desired output format at 8000 Hz
            let processingFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                               sampleRate: sampleRate,
                                               channels: 1,
                                               interleaved: false)!
            
            // Create a format converter
            let formatConverter = AVAudioConverter(from: hardwareFormat, to: processingFormat)
            
            // Install tap using hardware format
            inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: hardwareFormat) { [weak self] buffer, time in
                guard let self = self else { return }
                
                // Create an output buffer in our desired format
                guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: processingFormat,
                                                           frameCapacity: AVAudioFrameCount(Double(buffer.frameLength) * processingFormat.sampleRate / hardwareFormat.sampleRate)) else {
                    return
                }
                
                var error: NSError?
                
                // Convert the buffer
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                
                formatConverter!.convert(to: convertedBuffer,
                                     error: &error,
                                     withInputFrom: inputBlock)
                
                if error == nil {
                    // Process the converted buffer
                    self.processAudioBuffer(convertedBuffer)
                }
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
        
        // Apply Hanning window to reduce spectral leakage
        var window = [Float](repeating: 0, count: fftSize)
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        vDSP_vmul(realIn, 1, window, 1, &realIn, 1, vDSP_Length(fftSize))
        
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
        
        // Early exit: Check if we have any significant magnitude
        var maxMagnitude: Float = 0
        var maxIndex: vDSP_Length = 0
        vDSP_maxvi(magnitudes, 1, &maxMagnitude, &maxIndex, vDSP_Length(magnitudes.count))
        let peakFrequency = Float(maxIndex) * Float(sampleRate) / Float(fftSize)
        
        guard maxMagnitude > magnitudeThreshold else {
            DispatchQueue.main.async { [weak self] in
                self?.updateWithFrequency(nil)  // No significant sound detected
            }
            vDSP_destroy_fftsetup(fftSetup)
            return
        }
                
        // Define frequency range for guitar (E2 to E6)
        let minFreq: Float = 65.0   // Slightly below lowest guitar string (E2 = 82.41 Hz)
        let maxFreq: Float = 1000.0 // Well above highest guitar frequencies
        let minBin = Int(minFreq * Float(fftSize) / Float(sampleRate))
        let maxBin = Int(maxFreq * Float(fftSize) / Float(sampleRate))
        
        // Find the lowest significant peak
        var foundFrequency: Float? = nil
        var peakMagnitude: Float = magnitudeThreshold
        
        // Scan through the frequency bins
        for bin in minBin...maxBin {
            let magnitude = magnitudes[bin]
            
            // Check if this bin is a peak and above our threshold
            if magnitude > peakMagnitude {
                // Verify it's a local maximum
                if (bin == minBin || magnitudes[bin-1] < magnitude) &&
                   (bin == maxBin || magnitudes[bin+1] < magnitude) {
                    foundFrequency = interpolateFrequency(magnitudes: magnitudes, peakBin: bin)
                    // print("Max Magnitude: \(maxMagnitude), Peak Frequency: \(peakFrequency), Found mag: \(magnitude), Found freq: \(foundFrequency)")
                    break  // Stop at first significant peak (fundamental)
                }
            }
        }
        
        // Clean up FFT resources
        vDSP_destroy_fftsetup(fftSetup)
        
        // Update on main thread
        DispatchQueue.main.async { [weak self] in
            self?.updateWithFrequency(foundFrequency)
        }
    }
    
    // After finding the peak bin, interpolate using neighboring bins
    private func interpolateFrequency(magnitudes: [Float], peakBin: Int) -> Float {
        guard peakBin > 0 && peakBin < magnitudes.count - 1 else {
            return Float(peakBin) * Float(sampleRate) / Float(fftSize)
        }
        
        let alpha = magnitudes[peakBin-1]
        let beta = magnitudes[peakBin]
        let gamma = magnitudes[peakBin+1]
        
        // Quadratic interpolation
        let p = 0.5 * (alpha - gamma) / (alpha - 2*beta + gamma)
        let interpolatedBin = Float(peakBin) + p
        
        return interpolatedBin * Float(sampleRate) / Float(fftSize)
    }
    
    private func updateWithFrequency(_ frequency: Float?) {
        self.currentFrequency = frequency
        if let freq = frequency {
            let (note, cents) = findClosestNote(frequency: freq)
            self.closestNote = note
            self.cents = cents
        } else {
            // Reset the note display when no frequency is detected
            self.closestNote = Note(name: "", frequency: 0.0)
            self.cents = 0
        }
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
