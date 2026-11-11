# 서버시간 PiP (iOS)

네이비즘(time.navyism.com) 서버시간을 받아와서 **PiP(화면 속 화면)** 로 다른 앱 위에 띄워두는 시계 앱입니다.
티켓팅/캐치테이블 예약 등에서 대상 사이트의 서버시간을 보면서 다른 앱을 쓸 수 있습니다.

## 기능

| 기능 | 구현 |
| --- | --- |
| PiP 시계 | `AVSampleBufferDisplayLayer` 에 시계를 직접 그려 `AVPictureInPictureController` 로 띄움 (iOS 15+ API). 홈으로 나가면 자동으로 PiP 시작 |
| 링크로 네이비즘 서버시간 동기화 | 입력한 링크의 도메인으로 `https://time.navyism.com/?host=<도메인>` 페이지를 받아, 네이비즘 JS 와 같은 계산식으로 앱 시계를 맞춤 |
| 재동기화 버튼 | "서버시간 동기화" 버튼으로 언제든 다시 받아오기 |
| 직접 측정 (기본) | 앱이 대상 사이트에 직접 요청해 HTTP `Date` 헤더의 초 경계를 잡아 서버시간을 밀리초 단위로 측정. 튀는 샘플은 합의에서 제외하고 오차(±ms)·신뢰도·샘플 합의 수 표시 |
| 선행 클릭 | 왕복 지연의 절반 + 측정 오차를 권장 선행값으로 표시, 원하면 시계에 반영 |
| 내 사이트 저장 | 예매창 주소 등을 이름 붙여 저장 (길게 눌러 삭제) |

방식 선택: **자동**(직접 측정 → 실패 시 네이비즘) / **직접 측정** / **네이비즘**

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

### 1) 네이비즘 계산값 (`Sync/NavyismTimeSource.swift`)
네이비즘 페이지 `time.navyism.com/?host=<도메인>` 의 HTML 에는 시계 계산에 쓰는 값이 들어 있습니다.

```js
var mgap = 743;                 // 네이비즘 서버시각의 밀리초
var thisTime2 = 1794396026;     // 네이비즘 서버시각(초)
var mgval = new Date().getTime() - (thisTime2 * 1000 + mgap);
show(1794396026 - time() + 0);  // 대상 사이트 서버시각(초) - 네이비즘 시각 + 보정
mgval = mgval + 900;
```

앱은 이 HTML 을 받아서 **네이비즘 JS 와 같은 계산식**으로 오프셋을 구합니다. (웹뷰 없이 HTML 만 받음)
이 식이 네이비즘 원본 로직과 같은 결과를 내는지 무작위 2만 회 비교해서 확인했습니다.

참고: 네이비즘의 '밀리초' 표시는 초가 바뀔 때 40 부터 20씩 올라가는 장식용 카운터라 실제 밀리초가 아닙니다.
또 네이비즘 화면은 0.1초 간격으로 갱신되므로, 초가 바뀌는 순간이 앱보다 최대 0.1초 늦게 보일 수 있습니다.

### 2) 직접 측정 (`Sync/DirectServerTimeSource.swift`)
웹 서버 응답의 `Date` 헤더(1초 단위)를 이용합니다. 네이비즘은 대상 사이트와의 차이를 초 단위로만 반영하지만, 여기서는

- 요청 보낸 시각 t0, 받은 시각 t1, 헤더 시각 D 로부터 `D − t1 ≤ 오프셋 < D + 1 − t0`
- 서버의 **초 경계**에 요청이 도착하도록 보내는 시점을 조절하며 범위를 좁힘 (최대 12회, 충분히 좁혀지면 조기 종료)
- 가장 많은 샘플이 동의하는 구간을 고르고 동의하지 않는 샘플은 제외 (서버 여러 대·캐시 응답 대비)
- 리다이렉트는 따라가지 않음 (3xx 응답의 Date 도 유효, 왕복 1회만 측정)

결과 오차는 대략 왕복시간(RTT)의 절반입니다. 실제 서버 대상으로 Python 동일 구현으로 확인: chojeonghwak.com ±47ms (14/14 합의).

Cloudflare `/cdn-cgi/trace` 의 `ts=` 값도 검토했지만, 소수점 아래가 실제와 0~1초 사이로 무작위하게 어긋나
(정수 부분만 Date 와 같음) 밀리초 기준으로 쓸 수 없어 사용하지 않습니다.

### 3) PiP (`PiP/`)
- `ClockFrameRenderer`: 시계 문자열을 `CVPixelBuffer` 에 그려 `CMSampleBuffer` 로 변환
- `ClockFrameLoop`: 백그라운드에서도 동작하는 GCD 타이머(5ms)로, 표시 값이 바뀔 때만 새 프레임 공급
- `PiPClockController`: `AVPictureInPictureController` 연결. 앱 안의 미리보기 시계가 곧 PiP 원본

## 참고 / 한계
- 네이비즘이 봇 차단·페이지 개편 등으로 시계를 못 읽으면 **자동** 모드에서 직접 측정으로 넘어가고, 화면에 이유가 표시됩니다.
- 대부분의 대형 사이트는 CDN 을 쓰므로 "서버시간" = CDN 서버의 Date 헤더입니다. (네이비즘도 동일)
- PiP 는 오디오 백그라운드 모드를 사용합니다. App Store 배포 시 심사에서 용도 설명이 필요할 수 있습니다.
