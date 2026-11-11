import SwiftUI

/// PiP 크기(모양) 선택
struct PiPSizeView: View {
    @EnvironmentObject private var store: ClockStore

    var body: some View {
        List {
            Section {
                ForEach(PiPStyle.allCases) { style in
                    Button {
                        store.pipStyle = style
                    } label: {
                        HStack(spacing: 16) {
                            ShapeIcon(aspect: style.aspect)
                                .frame(width: 64, height: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.title).foregroundStyle(.primary)
                                Text(style.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if store.pipStyle == style {
                                Image(systemName: "checkmark").foregroundStyle(.blue).font(.headline)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            } footer: {
                Text("PiP 가 켜져 있어도 바로 바뀝니다. PiP 창 크기는 손가락으로 벌리거나 오므려 조절할 수 있고, 모양(비율)은 여기서 고른 것을 따릅니다.")
            }
        }
        .navigationTitle("PiP 크기")
    }
}

/// 비율을 보여주는 작은 아이콘
private struct ShapeIcon: View {
    var aspect: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * aspect)
            let h = w / aspect
            RoundedRectangle(cornerRadius: max(2, h * 0.2))
                .fill(Color.blue.opacity(0.7))
                .frame(width: w, height: max(2, h))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
