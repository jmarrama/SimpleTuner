import SwiftUI

struct TunerGauge: View {
    let cents: Float
    
    private let gradient = Gradient(colors: [
        .red,
        .orange,
        .yellow,
        .green,
        .yellow,
        .orange,
        .red
    ])
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background arc
                Circle()
                    .trim(from: 0.25, to: 0.75)
                    .stroke(
                        AngularGradient(
                            gradient: gradient,
                            center: .center,
                            startAngle: .degrees(180),
                            endAngle: .degrees(0)
                        ),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round)
                    )
                
                // Needle
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 4, height: geometry.size.height * 0.35)
                    .offset(y: -geometry.size.height * 0.17)
                    .rotationEffect(Angle(degrees: Double(min(max(cents, -50), 50)) * 1.8))
                    .shadow(radius: 2)
                
                // Center circle
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(radius: 2)
            }
        }
        .aspectRatio(2, contentMode: .fit)
        .padding()
    }
}
