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
    
    private var audioEngine = AVAudioEngine()
    private var noisePlayer = AVAudioPlayerNode()

    var body: some View {
        ZStack {
            // Background Gradient that changes with frequency and pitch
            LinearGradient(gradient: Gradient(colors: backgroundColors()), startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
                .gesture(
                    LongPressGesture(minimumDuration: 1.0)
                        .onEnded { _ in
                            if isPlaying {
                                inSliderMode = true
                                showHalo = true
                                print("SLIDERMODE activated.")
                            }
                        }
                        .simultaneously(with: DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if isPlaying && inSliderMode {
                                    let newPosition = value.location
                                    moveMarker(to: newPosition)
                                    updateNoiseParameters(from: newPosition)
                                    currentMarkerPosition = newPosition
                                }
                            }
                            .onEnded { _ in
                                if isPlaying && inSliderMode {
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
                                .stroke(showHalo ? Color.white.opacity(0.8) : Color.white.opacity(0.4), lineWidth: showHalo ? 4 : 2)
                                .frame(width: 30, height: 30) // Made slightly larger
                                .position(marker.position)
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
        }
        .onAppear {
            setupAudioChain()
            loadInitialState()
            updateUIBasedOnMarker()
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
    
    // Simplified audio setup
    private func setupAudioChain() {
        let output = audioEngine.outputNode
        let format = output.inputFormat(forBus: 0)
        
        let whiteNoise = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sampleVal = Float.random(in: -1.0...1.0) * self.frequency
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sampleVal * pow(2.0, self.pitch - 0.5)
                }
            }
            return noErr
        }

        audioEngine.attach(noisePlayer)
        audioEngine.attach(whiteNoise)

        audioEngine.connect(whiteNoise, to: output, format: format)
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
    }

    // Ensure the UI is correctly updated when the app loads
    private func updateUIBasedOnMarker() {
        if let marker = marker {
            updateNoiseParameters(from: marker.position)
        }
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
    }

    // Move marker to the specified position
    private func moveMarker(to position: CGPoint) {
        marker = Marker(position: position)
        UserDefaults.standard.saveMarker(marker!) // Save marker
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
