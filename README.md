# 서버시간 PiP (iOS)

네이비즘(time.navyism.com) 서버시간을 받아와서 **PiP(화면 속 화면)** 로 다른 앱 위에 띄워두는 시계 앱입니다.
티켓팅/캐치테이블 예약 등에서 대상 사이트의 서버시간을 보면서 다른 앱을 쓸 수 있습니다.

## 기능

| 기능 | 구현 |
| --- | --- |
| PiP 시계 | `AVSampleBufferDisplayLayer` 에 시계를 직접 그려 `AVPictureInPictureController` 로 띄움 (iOS 15+ API). 홈으로 나가면 자동으로 PiP 시작 |
| 링크로 네이비즘 서버시간 동기화 | 입력한 링크의 도메인으로 `https://time.navyism.com/?host=<도메인>` 을 숨겨진 WebView 로 열고, 페이지에 표시되는 시계를 읽어 앱 시계를 맞춤 |
| 재동기화 버튼 | "서버시간 동기화" 버튼으로 언제든 다시 받아오기 |
| 직접 측정 (대안) | 네이비즘이 안 되면 앱이 대상 사이트에 직접 요청해 HTTP `Date` 헤더로 서버시간을 밀리초 단위까지 측정 |

방식 선택: **자동**(네이비즘 → 실패 시 직접 측정) / **네이비즘** / **직접 측정**

## 빌드 방법

Xcode 프로젝트는 [XcodeGen](https://github.com/yonaskolb/XcodeGen) 으로 생성합니다.

```bash
brew install xcodegen
xcodegen            # PipServerTime.xcodeproj 생성
open PipServerTime.xcodeproj
```

1. Signing & Capabilities 에서 본인 Team 선택 (필요하면 Bundle ID 변경)
2. Background Modes 의 **Audio, AirPlay, and Picture in Picture** 가 켜져 있는지 확인 (Info.plist `UIBackgroundModes = audio` 로 이미 설정됨)
3. **실기기**에서 실행 (시뮬레이터는 PiP 동작이 제한적)

요구사항: iOS 16+, Xcode 15+

## 동작 원리

### 1) 네이비즘에서 가져오기 (`Sync/NavyismTimeSource.swift`)
네이비즘은 공개 API 가 없고, 페이지의 JavaScript 가 대상 서버시간 시계를 그려 줍니다.
그래서 앱은:

1. 화면에 보이지 않는 `WKWebView` 로 `time.navyism.com/?host=app.catchtable.co.kr` 같은 주소를 엽니다.
2. 페이지에서 `19시 16분 00초` 또는 `19:16:00` 형태의 글자를 가진 요소를 찾습니다.
   (고정된 시각 문구는 무시하고, **실제로 값이 바뀌는 요소**를 시계로 판단)
3. 4ms 간격으로 감시하다가 **초가 바뀌는 순간**(= 네이비즘 기준 xx.000초)의 기기 시각과 비교해 오프셋을 계산합니다. 2회 측정해 평균.

내부 변수명이 아닌 *화면에 표시되는 글자*를 읽기 때문에 네이비즘 페이지 구조가 조금 바뀌어도 동작하도록 만들었습니다.
시간대(KST/기기 시간대) 차이에 영향받지 않도록 분·초만 비교합니다.

### 2) 직접 측정 (`Sync/DirectServerTimeSource.swift`)
네이비즘이 쓰는 원리와 같습니다. 웹 서버 응답의 `Date` 헤더(1초 단위)를 이용하되,

- 요청 보낸 시각 t0, 받은 시각 t1, 헤더 시각 D 로부터 `D − t1 ≤ 오프셋 < D + 1 − t0`
- 서버의 **초 경계**에 요청이 도착하도록 보내는 시점을 조절하며 범위를 이분 탐색으로 좁힘 (10회)

결과 오차는 대략 왕복시간(RTT)의 절반입니다. (RTT 40ms 기준 시뮬레이션 ±25ms 이내)

### 3) PiP (`PiP/`)
- `ClockFrameRenderer`: 시계 문자열을 `CVPixelBuffer` 에 그려 `CMSampleBuffer` 로 변환
- `ClockFrameLoop`: 백그라운드에서도 동작하는 GCD 타이머(5ms)로, 표시 값이 바뀔 때만 새 프레임 공급
- `PiPClockController`: `AVPictureInPictureController` 연결. 앱 안의 미리보기 시계가 곧 PiP 원본

## 참고 / 한계
- 네이비즘이 봇 차단·페이지 개편 등으로 시계를 못 읽으면 **자동** 모드에서 직접 측정으로 넘어가고, 화면에 이유가 표시됩니다.
- 대부분의 대형 사이트는 CDN 을 쓰므로 "서버시간" = CDN 서버의 Date 헤더입니다. (네이비즘도 동일)
- PiP 는 오디오 백그라운드 모드를 사용합니다. App Store 배포 시 심사에서 용도 설명이 필요할 수 있습니다.
