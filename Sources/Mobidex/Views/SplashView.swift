import SwiftUI

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPresented = false
    @State private var showProgress = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                MobidexSplashMark()
                    .frame(width: 96, height: 96)
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 10)

                VStack(spacing: 10) {
                    Text("Mobidex")
                        .font(.system(size: 36, weight: .semibold, design: .rounded))
                        .foregroundStyle(.primary)

                    loadingIndicator
                }
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

private struct MobidexSplashMark: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.13, green: 0.12, blue: 0.28),
                            Color(red: 0.02, green: 0.05, blue: 0.11)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Text(">")
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .offset(x: -17, y: -3)

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.68, green: 0.18, blue: 0.98),
                            Color(red: 0.18, green: 0.87, blue: 0.96)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: 36, height: 8)
                .offset(x: 22, y: 25)
        }
        .accessibilityHidden(true)
    }
}
