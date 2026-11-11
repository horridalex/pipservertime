import SwiftUI

/// PiP 크기(모양) 선택
struct PiPSizeView: View {
    @EnvironmentObject private var store: ClockStore

    var body: some View {
        CardScreen {
            SettingsCard {
                ForEach(PiPStyle.allCases) { style in
                    if style != PiPStyle.allCases.first { RowDivider() }
                    Button {
                        store.pipStyle = style
                    } label: {
                        HStack(spacing: 16) {
                            ShapeIcon(aspect: style.aspect, selected: store.pipStyle == style)
                                .frame(width: 64, height: 40)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(style.title).foregroundStyle(Theme.ink)
                                Text(style.subtitle).font(.footnote).foregroundStyle(Theme.secondary)
                            }
                            Spacer()
                            Image(systemName: "checkmark").font(.body.weight(.bold))
                                .foregroundStyle(Theme.accentText)
                                .opacity(store.pipStyle == style ? 1 : 0)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 8)
            Text("PiP 가 켜져 있어도 바로 바뀌어요. 창 크기는 손가락으로 벌리거나 오므려 조절하고, 모양(비율)은 여기서 고른 것을 따라요.")
                .font(.footnote).foregroundStyle(Theme.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 4)
        }
        .navigationTitle("PiP 크기")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 비율을 보여주는 작은 아이콘 (선택된 것만 민트)
private struct ShapeIcon: View {
    var aspect: CGFloat
    var selected: Bool

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * aspect)
            let h = max(3, w / aspect)
            RoundedRectangle(cornerRadius: max(2, h * 0.2))
                .stroke(selected ? Theme.accent : Theme.secondary, lineWidth: 2)
                .background(RoundedRectangle(cornerRadius: max(2, h * 0.2))
                    .fill(selected ? Theme.accent.opacity(0.35) : Color.clear))
                .frame(width: w - 2, height: h)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
