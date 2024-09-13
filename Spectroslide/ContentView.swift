import SwiftUI
import AVFoundation

struct ContentView: View {
    @State private var isPlaying = false
    @State private var frequency: Float = 0.5 // Vertical control (deep to sharp noise)
    @State private var pitch: Float = 0.5 // Horizontal control (low to high pitch)
    
    private var audioEngine = AVAudioEngine()
    private var noisePlayer = AVAudioPlayerNode()
    private var eqNode = AVAudioUnitEQ(numberOfBands: 2)
    
    var body: some View {
        ZStack {
            // Background Gradient that changes with frequency and pitch
            LinearGradient(gradient: Gradient(colors: backgroundColors()), startPoint: .topLeading, endPoint: .bottomTrailing)
                .edgesIgnoringSafeArea(.all)
                .hueRotation(Angle(degrees: Double(pitch) * 10)) // Subtle hue shift based on pitch
                .opacity(0.7 + Double(pitch) * 0.3) // Adjust opacity with pitch
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateNoiseParameters(from: value)
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
    
    // Function to setup the audio chain with EQ effects
    private func setupAudioChain() {
        let output = audioEngine.outputNode
        let format = output.inputFormat(forBus: 0)
        
        let whiteNoise = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            for frame in 0..<Int(frameCount) {
                let sampleVal = self.generateNoiseSample()
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sampleVal
                }
            }
            return noErr
        }
        
        // EQ Configuration
        eqNode.globalGain = 1.0
        
        // Low-Pass Filter to enhance bass
        let bassBand = eqNode.bands[0]
        bassBand.filterType = .lowPass
        bassBand.frequency = 150 // Lower frequency for deeper bass
        bassBand.gain = 15.0 // High gain to emphasize bass
        
        // Band-Pass Filter to focus on lower mids
        let midBand = eqNode.bands[1]
        midBand.filterType = .bandPass
        midBand.frequency = 500 // Mid-range frequency
        midBand.bandwidth = 1.5 // Narrower band for sharper effect
        midBand.gain = 5.0
        
        audioEngine.attach(noisePlayer)
        audioEngine.attach(whiteNoise)
        audioEngine.attach(eqNode)
        
        // Connect nodes
        audioEngine.connect(whiteNoise, to: eqNode, format: format)
        audioEngine.connect(eqNode, to: output, format: format)
    }
    
    // Function to start noise with adjustable frequency and pitch
    private func startNoise() {
        try? audioEngine.start()
    }
    
    // Function to stop the noise
    private func stopNoise() {
        audioEngine.pause()
    }
    
    // Generate a noise sample based on the current frequency and pitch
    private func generateNoiseSample() -> Float {
        let baseNoise = Float.random(in: -1.0...1.0)
        let adjustedNoise = baseNoise * frequency * 0.5 // Adjusting for intensity
        let pitchedNoise = adjustedNoise * pow(2.0, pitch - 0.5) // Pitch control
        return pitchedNoise
    }
    
    // Update frequency and pitch based on drag gesture position
    private func updateNoiseParameters(from value: DragGesture.Value) {
        let dragX = Float(value.location.x / UIScreen.main.bounds.width)
        let dragY = Float(value.location.y / UIScreen.main.bounds.height)
        
        pitch = max(0.2, min(dragX, 0.8)) // Horizontal drag controls pitch
        frequency = max(0.2, min(1.0 - dragY, 0.8)) // Vertical drag controls frequency
        
        // Dynamically adjust EQ parameters based on user input
        eqNode.bands[0].gain = frequency * 24.0 - 12.0 // Adjust gain dynamically for bass
        eqNode.bands[1].frequency = pitch * 1000.0 + 200.0 // Adjust frequency for mid-band
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

#Preview {
    ContentView()
}

