import SwiftUI

/// 처음 실행할 때 보여주는 사용법 (설정 › 사용법에서도 다시 볼 수 있음)
struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var page = 0

    private struct Step: Identifiable {
        let id: Int
        let icon: String
        let title: String
        let body: String
    }

    private let steps: [Step] = [
        Step(id: 0, icon: "globe",
             title: "1. 사이트 고르기",
             body: "시계 카드 위의 사이트 버튼을 눌러 예매할 사이트를 골라요.\n가장 정확한 건 예매 버튼을 눌렀을 때 열리는 예매창 주소예요. 직접 넣고 '내 사이트'로 저장해 두세요."),
        Step(id: 1, icon: "arrow.triangle.2.circlepath",
             title: "2. 동기화",
             body: "'동기화'를 누르면 앱이 사이트 서버에 직접 여러 번 물어봐서 서버시간을 밀리초 단위로 맞춰요.\n와이파이에서, 오픈 몇 분 전에 측정할수록 정확해요."),
        Step(id: 2, icon: "pip.enter",
             title: "3. 팝업 타이머",
             body: "'팝업 타이머'를 누르면 다른 앱 위에 시계가 떠요. 예매 앱으로 넘어가 시계를 보며 누르세요.\n지정한 시각에 팝업이 자동으로 닫히게 할 수도 있어요."),
        Step(id: 3, icon: "slider.horizontal.3",
             title: "4. 미세 조정",
             body: "팝업 창의 ◀◀ / ▶▶ 버튼으로 시계를 조금씩 늦추거나 앞당길 수 있어요.\n'연습'에서 내 반응속도를 재서 시계에 반영해 두면 더 제때 누를 수 있어요."),
        Step(id: 4, icon: "calendar.badge.clock",
             title: "5. 일정 등록",
             body: "오픈 시각을 등록하면 카운트다운이 뜨고, 5분·1분 전에 알림을 보내고, 오픈 1분 30초 전에 자동으로 다시 측정해요.\n자동 재측정은 앱이나 팝업 타이머가 켜져 있을 때 동작해요."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("건너뛰기") { dismiss() }
                    .foregroundStyle(Theme.secondary)
                    .padding(16)
            }

            TabView(selection: $page) {
                ForEach(steps) { step in
                    VStack(spacing: 24) {
                        Spacer()
                        Image(systemName: step.icon)
                            .font(.system(size: 56, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 120, height: 120)
                            .background(Circle().fill(Theme.card))
                            .overlay(Circle().stroke(Theme.border))
                        Text(step.title)
                            .font(.title2.weight(.heavy))
                            .foregroundStyle(Theme.ink)
                        Text(step.body)
                            .font(.body)
                            .foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .padding(.horizontal, 28)
                        Spacer()
                        Spacer()
                    }
                    .tag(step.id)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(page == steps.count - 1 ? "시작하기" : "다음") {
                if page == steps.count - 1 {
                    dismiss()
                } else {
                    withAnimation { page += 1 }
                }
            }
            .buttonStyle(CapsuleButtonStyle(filled: true))
            .padding(16)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
