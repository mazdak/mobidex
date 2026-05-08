import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var showProgress = false

    var body: some View {
        ZStack {
            Color("LaunchBackground")
                .ignoresSafeArea()

            ZStack {
                Image("LaunchLogo")
                    .accessibilityHidden(true)

                loadingIndicator
                    .offset(y: 76)
            }
            .padding(32)
            .scaleEffect(isPresented ? 1 : 0.96)
            .opacity(isPresented ? 1 : 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mobidex loading")
        .onAppear {
            if reduceMotion {
                isPresented = true
            } else {
                withAnimation(.spring(response: 0.46, dampingFraction: 0.82)) {
                    isPresented = true
                }
                withAnimation(.easeIn(duration: 0.20).delay(0.20)) {
                    showProgress = true
                }
            }
        }
    }

    @ViewBuilder
    private var loadingIndicator: some View {
        if reduceMotion {
            Capsule()
                .fill(Color.secondary.opacity(0.28))
                .frame(width: 36, height: 4)
                .accessibilityHidden(true)
        } else {
            ProgressView()
                .controlSize(.small)
                .tint(.secondary)
                .opacity(showProgress ? 1 : 0)
        }
    }
}
