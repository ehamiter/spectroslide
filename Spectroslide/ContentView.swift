import SwiftUI
import AVFoundation

// Wrapper struct for CGPoint that conforms to Hashable
struct Marker: Hashable {
    let id = UUID()
    var position: CGPoint

    static func == (lhs: Marker, rhs: Marker) -> Bool {
        return lhs.id == rhs.id && lhs.position == rhs.position
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(position.x)
        hasher.combine(position.y)
    }
}

struct ContentView: View {
    @State private var isPlaying = false
    @State private var inSliderMode = false // Track if SLIDERMODE is active
    @State private var frequency: Float = 0.5 // Default to pink noise
    @State private var pitch: Float = 0.5 // Default to middle pitch
    @State private var marker: Marker? = UserDefaults.standard.savedMarker() // Load saved marker
    @State private var showHalo = false // Track halo visibility
    @State private var currentMarkerPosition: CGPoint? = nil // Track the current marker position during the gesture
    @State private var showTip: Bool = true // Default to show tip on first launch
    
    private var audioEngine = AVAudioEngine()
    private var noisePlayer = AVAudioPlayerNode()
    private var equalizer = AVAudioUnitEQ(numberOfBands: 3) // Simplified EQ
    
    // State for smoothing the noise
    @State private var smoothingState: Float = 0.0

    // Move marker to the specified position
    private func moveMarker(to position: CGPoint) {
        marker = Marker(position: position)
        UserDefaults.standard.saveMarker(marker!) // Save marker
    }

    // Load initial state
    private func loadInitialState() {
        if let savedMarker = marker {
            frequency = Float(savedMarker.position.y / UIScreen.main.bounds.height)
            pitch = Float(savedMarker.position.x / UIScreen.main.bounds.width)
        } else {
            frequency = 0.5 // Default to middle
            pitch = 0.5 // Default to middle
        }
        showHalo = false
    }

    // Set initial marker for first-time users
    private func setInitialMarker() {
        let initialPosition = CGPoint(x: UIScreen.main.bounds.width * 0.25, y: UIScreen.main.bounds.height * 0.5)
        marker = Marker(position: initialPosition)
        UserDefaults.standard.saveMarker(marker!)
        updateNoiseParameters(from: initialPosition)
        showHalo = false
    }

    // Ensure the UI is correctly updated when the app loads
    private func updateUIBasedOnMarker() {
        if let marker = marker {
            updateNoiseParameters(from: marker.position)
        }
    }

    
    var body: some View {
        ZStack {
            // Background Gradient that changes with frequency and pitch
            LinearGradient(gradient: Gradient(colors: backgroundColors()), startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
                .brightness(Double(0.5 - pitch) * 0.3)
                .gesture(
                    LongPressGesture(minimumDuration: 0.75)
                        .onEnded { _ in
                            inSliderMode = true
                            showHalo = true
                            showTip = false
                            UserDefaults.standard.set(false, forKey: "showTip")
                            print("SLIDERMODE activated.")
                        }
                        .simultaneously(with: DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if inSliderMode {
                                    let newPosition = value.location
                                    moveMarker(to: newPosition)
                                    updateNoiseParameters(from: newPosition)
                                    currentMarkerPosition = newPosition
                                }
                            }
                            .onEnded { _ in
                                if inSliderMode {
                                    inSliderMode = false
                                    showHalo = false
                                    print("SLIDERMODE deactivated.")
                                }
                            }
                        )
                )
                .overlay(
                    Group {
                        if let marker = marker {
                            Circle()
                                .stroke(showHalo ? Color.white.opacity(0.8) : Color.white.opacity(0.4), lineWidth: showHalo ? 6 : 2)
                                .frame(width: showHalo ? 40 : 30, height: showHalo ? 40 : 30) // Increased size when halo is active
                                .scaleEffect(showHalo ? 1.2 : 1.0) // Slight scaling effect for attention
                                .position(marker.position)
                                .animation(showHalo ? .easeInOut(duration: 0.6).repeatForever(autoreverses: true) : .default, value: showHalo) // Pulsating animation only when showHalo is true
                        }
                    }
                )
            
            // Central Button
            Button(action: toggleNoise) {
                Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(.white)
                    .shadow(radius: 10)
            }

            // First-Time Tip
            if showTip {
                VStack {
                    Spacer()
                    HStack {
                        Text("Press the screen for one second, then slide!")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(10)
                    }
                    .padding(.bottom, 100)
                    .onAppear {
                        showHalo = false
                    }
                }
            }
        }
        .onAppear {
            setupAudioChain()
            loadInitialState()
            if UserDefaults.standard.bool(forKey: "hasLaunchedBefore") == false {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                setInitialMarker()
            } else {
                updateUIBasedOnMarker()
                showTip = false
            }
            showHalo = false
        }
    }
    
    // Toggle the noise on and off
    private func toggleNoise() {
        if isPlaying {
            stopNoise()
        } else {
            startNoise()
        }
        isPlaying.toggle()
    }
    
    // Enhanced audio setup with proper colored noise generation
    private func setupAudioChain() {
        // Configure audio session to play sound even when device is in silent mode
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            print("Failed to configure audio session: \(error)")
        }
        
        let output = audioEngine.outputNode
        let format = output.inputFormat(forBus: 0)
        
        // Generate clean, simple noise
        let cleanNoise = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                // Generate raw white noise
                let rawNoise = Float.random(in: -1.0...1.0)
                
                // Apply smoothing filter to make it sound "slower" and more flowing
                let smoothingAmount: Float = 0.999 // Very heavy smoothing for flowing sound
                self.smoothingState = self.smoothingState * smoothingAmount + rawNoise * (1.0 - smoothingAmount)
                
                // Final sample with proper volume
                let sample = self.smoothingState * 1.1 // Increased volume for better listening levels
                
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample
                }
            }
            return noErr
        }

        // Simple setup - just noise and basic EQ
        audioEngine.attach(cleanNoise)
        audioEngine.attach(equalizer)
        
        // Configure simple EQ
        setupSimpleEQ()
        
        // Simple connection: noise -> EQ -> output
        audioEngine.connect(cleanNoise, to: equalizer, format: format)
        audioEngine.connect(equalizer, to: output, format: format)
    }
    
    // Configure simple, clean EQ with better bass
    private func setupSimpleEQ() {
        // Simple 3-band EQ: Low, Mid, High - optimized for bass
        equalizer.bands[0].frequency = 60.0   // Lower frequency for real bass
        equalizer.bands[0].gain = 0.0
        equalizer.bands[0].bandwidth = 1.5
        equalizer.bands[0].filterType = .lowShelf
        equalizer.bands[0].bypass = false
        
        equalizer.bands[1].frequency = 800.0  // Mid frequencies  
        equalizer.bands[1].gain = 0.0
        equalizer.bands[1].bandwidth = 2.0
        equalizer.bands[1].filterType = .parametric
        equalizer.bands[1].bypass = false
        
        equalizer.bands[2].frequency = 6000.0 // High frequencies
        equalizer.bands[2].gain = 0.0
        equalizer.bands[2].bandwidth = 1.5
        equalizer.bands[2].filterType = .highShelf
        equalizer.bands[2].bypass = false
    }
    


    // Start noise playback
    private func startNoise() {
        try? audioEngine.start()
    }

    // Stop noise playback
    private func stopNoise() {
        audioEngine.pause()
    }

    // Update frequency and pitch based on position
    private func updateNoiseParameters(from position: CGPoint) {
        let dragX = Float(position.x / UIScreen.main.bounds.width)
        let dragY = Float(position.y / UIScreen.main.bounds.height)
        
        pitch = max(0.2, min(dragX, 0.8)) // Horizontal drag controls pitch
        frequency = max(0.2, min(1.0 - dragY, 0.8)) // Vertical drag controls frequency
        
        // Update simple EQ settings based on position
        updateSimpleEQ()
    }
    
    // Adjust simple EQ settings based on slider position
    private func updateSimpleEQ() {
        // Frequency parameter controls the overall tone character
        // Top to bottom: Red → Pink → Brown noise characteristics
        if frequency < 0.33 {
            // Brown noise (bottom): Deep, rumbling bass emphasis
            equalizer.bands[0].gain = 15.0  // Strong bass boost for brown noise
            equalizer.bands[1].gain = -2.0  // Slight mid cut
            equalizer.bands[2].gain = -10.0 // Strong high cut
        } else if frequency < 0.67 {
            // Pink noise (middle): Balanced, natural sound
            equalizer.bands[0].gain = 8.0   // Moderate bass boost for pink noise
            equalizer.bands[1].gain = 0.0   // Keep mids neutral  
            equalizer.bands[2].gain = -6.0  // Moderate high cut
        } else {
            // Red noise (top): Maximum low-frequency emphasis
            equalizer.bands[0].gain = 20.0  // Maximum bass boost for red noise
            equalizer.bands[1].gain = -3.0  // Cut mids more
            equalizer.bands[2].gain = -15.0 // Maximum high cut
        }
    }

    // Generate background colors based on the frequency range for different noise types
    private func backgroundColors() -> [Color] {
        if frequency < 0.4 {
            // Brown Noise (Darker to lighter for deeper bass)
            return [
                Color(red: 0.3, green: 0.1, blue: 0.0), // Darker
                Color(red: 0.4, green: 0.2, blue: 0.1)  // Lighter
            ]
        } else if frequency < 0.7 {
            // Pink Noise (Softer pink to brighter pink)
            return [
                Color(red: 0.8, green: 0.5, blue: 0.5), // Softer pink
                Color(red: 1.0, green: 0.7, blue: 0.7)  // Brighter pink
            ]
        } else {
            // Red Noise (Darker red to brighter red)
            return [
                Color(red: 0.6, green: 0.1, blue: 0.1), // Darker red
                Color(red: 0.9, green: 0.2, blue: 0.2)  // Brighter red
            ]
        }
    }
}

// UserDefaults extension to save and load the marker
extension UserDefaults {
    func saveMarker(_ marker: Marker) {
        let data = ["x": marker.position.x, "y": marker.position.y]
        set(data, forKey: "marker")
    }
    
    func savedMarker() -> Marker? {
        guard let data = dictionary(forKey: "marker") as? [String: CGFloat],
              let x = data["x"], let y = data["y"] else { return nil }
        return Marker(position: CGPoint(x: x, y: y))
    }
}

#Preview {
    ContentView()
}
