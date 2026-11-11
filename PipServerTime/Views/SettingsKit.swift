import SwiftUI

// 설정·목록 화면 공통 부품: 짙은 카드 + 흰 제목 + 회색 설명/값/화살표, 민트는 토글·값·± 버튼에만

/// 카드 위 작은 회색 제목
struct SectionHeader: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 14)
    }
}

/// 둥근 카드에 행들을 쌓음 (행 사이 구분선은 RowDivider)
struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.border))
    }
}

struct RowDivider: View {
    var body: some View {
        Rectangle().fill(Theme.border).frame(height: 1).padding(.leading, 20)
    }
}

/// 카드 안 설명 문단
struct CardNote: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(Theme.secondary)
            .lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 18)
    }
}

/// 기본 행 레이아웃
struct RowLabel<Trailing: View>: View {
    var title: String
    var subtitle: String? = nil
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
    }
}

/// › 가 붙은 이동 행
struct NavRow<Destination: View>: View {
    var title: String
    var value: String? = nil
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink { destination } label: {
            RowLabel(title: title) {
                if let value { Text(value).foregroundStyle(Theme.secondary) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 토글 행
struct ToggleRow: View {
    var title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        RowLabel(title: title, subtitle: subtitle) {
            Toggle("", isOn: $isOn).labelsHidden().tint(Theme.accent)
        }
    }
}

/// 값을 고르는 행 (누르면 메뉴)
struct MenuRow<T: Hashable>: View {
    var title: String
    @Binding var selection: T
    var options: [(T, String)]

    var body: some View {
        Menu {
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { i in Text(options[i].1).tag(options[i].0) }
            }
        } label: {
            RowLabel(title: title) {
                Text(options.first { $0.0 == selection }?.1 ?? "").foregroundStyle(Theme.secondary)
                Image(systemName: "chevron.up.chevron.down").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

/// − 값 + 행 (민트 버튼)
struct StepRow: View {
    var title: String
    var value: String
    var minus: () -> Void
    var plus: () -> Void

    var body: some View {
        RowLabel(title: title) {
            HStack(spacing: 14) {
                stepButton("minus", minus).accessibilityLabel("줄이기")
                Text(value).font(.body.monospaced().weight(.semibold)).foregroundStyle(Theme.accentText)
                    .frame(minWidth: 64)
                stepButton("plus", plus).accessibilityLabel("늘리기")
            }
        }
    }

    private func stepButton(_ name: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name).font(.body.weight(.bold)).foregroundStyle(Theme.accentText)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// 체크로 고르는 행
struct CheckRow: View {
    var title: String
    var subtitle: String? = nil
    var checked: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            RowLabel(title: title, subtitle: subtitle) {
                Image(systemName: "checkmark").font(.body.weight(.bold))
                    .foregroundStyle(Theme.accentText).opacity(checked ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
    }
}

/// 카드 화면 공통 바탕
struct CardScreen<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        ScrollView {
            VStack(spacing: 10) { content }
                .padding(.horizontal, 16)
                .padding(.bottom, 40)
        }
        .background(Theme.bg.ignoresSafeArea())
    }
}
