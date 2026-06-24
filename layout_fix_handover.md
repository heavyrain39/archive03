# 레이아웃 수정 작업 인수인계 (Layout Fix Handover)

**일시:** 2026-01-03
**상태:** 미해결 (Unresolved) - 11개 항목 중 7~8개만 표시되는 현상 지속됨.

## 🚨 현재 문제 상황 (Current Issues)
1.  **게시물 목록 잘림**: 대시보드 우측 'Articles' 카드에 11개의 항목이 표시되어야 하지만, 약 **7~8개**만 보이고 나머지는 잘림.
2.  **높이 과소평가 (Underestimation)**:
    - JavaScript 로직은 정상적으로 실행되어 높이를 계산하고 있습니다.
    - 로그: `Calculated True Heights: {headerHeight: 26, listHeight: 524, footerHeight: 63, totalHeight: 673}`
    - **문제점**: 11개 항목의 높이가 `524px`로 측정되고 있는데, 이는 항목당 약 `47px`에 불과합니다. 실제 UI에서 항목의 높이가 이보다 크다면(예: 60px 이상), 524px은 턱없이 부족한 공간이며, 결과적으로 리스트가 잘리게 됩니다.
3.  **레이아웃 적용 의문**: 계산된 `totalHeight: 673px`가 Grid Row에 적용되더라도, 화면상에서는 여전히 영역이 부족해 보입니다.

---

## 🛠️ 시도한 해결책들 (Failed Attempts)

### 1단계: 단순 Unlock Strategy
- **방법**: `.post-list`의 `position`을 `relative`로 변경 후 측정.
- **결과**: 부모인 `.post-list-wrapper`의 `absolute/height:100%` 제약 때문에 측정 실패.

### 2단계: Nuclear Option
- **방법**: 래퍼와 리스트 모두 `static`, `height: auto`, `overflow: visible`로 변경 후 측정.
- **결과**: `offsetHeight`로는 여전히 잘린 높이만 반환됨.

### 3단계: ScrollHeight Strategy (with Claude)
- **방법**: 위의 Unlock 상태에서 `scrollHeight`로 측정.
- **결과**: 실패. `Multiple Lists Issue`(애니메이션 중 이전 리스트 측정) 가능성 제기됨.

### 4단계: Clone Strategy (Basic)
- **방법**: 리스트를 복제하여 `document.body`에 붙여서 측정.
- **결과**: 실패. `body` 전체 너비를 사용하면서 텍스트 줄바꿈이 사라져 높이가 504px로 매우 낮게 측정됨.

### 5단계: Context-Preserved Clone Strategy
- **방법**: 복제된 리스트를 `.post-list-container` 내부에 붙이고, 너비를 강제함.
- **결과**: 실패. 여전히 524px 수준으로 측정됨.

### 6단계: Exact-Width Clone Strategy (Current)
- **방법**:
    - `targetList.getBoundingClientRect().width`로 1px 단위의 정확한 너비 추출.
    - `position: absolute`로 래퍼 내부에 복제하여 레이아웃 컨텍스트 일치시킴.
    - `box-sizing`, `padding` 등 스타일 미러링.
- **결과**: **실패**. 여전히 `listHeight: 524`로 측정되며 8개만 표시됨.

---

## 🕵️‍♂️ 다음 단계를 위한 분석 및 제안 (Next Steps)

높이가 `524px`로 계속 측정되는 것이 "정확한 값"인지, 아니면 "여전히 왜곡된 값"인지가 불분명합니다. 하지만 결과적으로 잘린다면 **왜곡된 값(과소평가)**일 가능성이 높습니다.

### 1. 아이템별 높이 전수 조사 (Item Height Audit)
- **가설**: CSS 간섭(예: `line-height`, `margin-collapse`)으로 인해, 클론 내부의 `li`들이 실제보다 더 다닥다닥 붙어서 렌더링되고 있을 수 있습니다.
- **액션**: 콘솔에서 다음을 실행하여 실제 `li` 하나의 높이를 확인해야 합니다.
  ```javascript
  // Chrome Console
  document.querySelector('.post-list li').offsetHeight // 예: 65px라면 11개면 715px여야 함.
  ```
- 만약 실제 `li`가 65px인데 클론 측정값이 524px라면, 클론 내부 스타일이 깨진 것입니다.

### 2. Grid 스타일 강제 적용 테스트 (Hardcoding Test)
- **가설**: JS가 `gridTemplateRows`를 설정해도, CSS의 `!important`나 미디어 쿼리에 의해 무시되고 있을 수 있습니다.
- **액션**: JS 코드 내에서 계산 로직을 무시하고 강제로 값을 주입해 봅니다.
  ```javascript
  gridContainer.style.gridTemplateRows = "1000px auto"; // 무식하게 크게 줘봄
  ```
  이래도 안 늘어나면 CSS 문제입니다.

### 3. CSS 정밀 검사
- `assets/css/style.scss` 내에 `.post-list-card`나 `.dashboard-container`에 `max-height`가 걸려 있는지 다시 확인해야 합니다.
- 특히 모바일/태블릿(`max-width: 820px`) 관련 미디어 쿼리가 데스크탑에도 영향을 주는지 확인이 필요합니다.

### 4. 폰트 로딩 타이밍 (Font Loading)
- 폰트 로딩 전/후의 줄바꿈 차이가 높이에 치명적일 수 있습니다. `document.fonts.ready.then(...)`이 확실히 작동하는지 체크하세요.

---

**결론**: "계산된 높이(524px)"가 "실제 필요한 높이"보다 작다는 것이 거의 확실해 보입니다. 다음 세션에서는 **'왜 클론의 높이가 실제보다 작게 나오는가?'**에 집중하거나, 아예 **'아이템 개수 × 고정 높이(예: 65px)'** 같은 산술적 방식(Heuristic)으로 선회하는 것도 고려해 볼 만합니다.

---

## 🟢 [RESOLVED] 레이아웃 높이 잘림 문제 해결 (2026-01-03)

**상태:** 해결 완료 (Resolved)
**핵심 원인:** Grid의 `align-items: start` 속성과 `position: absolute` 자식 요소 간의 충돌.

### 1. 원인 분석 (Root Cause Analysis)
*   **현상:** JavaScript가 Grid Row의 높이를 800px 이상으로 정확히 계산하여 늘렸음에도, 우측 'Articles' 카드는 늘어나지 않고 `min-height` (460px)에 머물러 콘텐츠가 7개만 보이고 잘림.
*   **이유:**
    1.  `.dashboard-container`에 **`align-items: start`**가 적용되어 있어, Grid Item(카드)들이 Row 높이에 맞춰 늘어나지 않고(stretch) 자신의 콘텐츠 크기만큼만 차지함.
    2.  리스트 내부 (`ul.post-list`)가 애니메이션을 위해 **`position: absolute`**로 설정됨.
    3.  브라우저는 우측 카드의 콘텐츠 높이를 '0'으로 인식하고, CSS에 지정된 최소 높이(460px)까지만 렌더링함.
    4.  결국 Row 높이는 늘어났으나, 카드는 늘어나지 않아 시각적 불일치 발생.

### 2. 최종 해결책: "Snug Fit Strategy" (정밀 맞춤 전략)
단순히 Grid Row만 늘리는 것이 아니라, **우측 카드 자체의 높이를 강제로 주입**하여 해결함.

*   **로직 변경:**
    1.  **Clone 폐기:** 복제본 측정 방식은 부정확하여 폐기.
    2.  **Live Item 측정:** 실제 렌더링된 `li` 아이템 하나를 `getBoundingClientRect`로 정밀 측정. (약 46px 내외)
    3.  **여백 확보:** 시각적 균형을 위해 `padding-top: 15px`, `padding-bottom: 10px`을 JS로 강제 주입하고 계산식에 포함.
    4.  **강제 주입 (Force Injection):** 계산된 `snugHeight`를 다음 세 곳에 모두 적용.
        *   Grid Container (`gridTemplateRows`)
        *   Left Card (`style.height` -> 이미지 크롭 유도)
        *   **Right Card (`style.height` -> ★핵심 솔루션)**

### 3. 향후 유지보수 시 주의사항 (To Future Maintainers)
이 코드를 수정할 때 다음 사항을 절대 건드리지 마십시오.

1.  **우측 카드의 높이 강제 설정을 삭제하지 말 것:**
    ```javascript
    rightCard.style.height = `${snugHeight}px`; // 이거 지우면 다시 7개만 나옴
    ```
2.  **CSS `align-items` 속성 주의:** 만약 CSS에서 `align-items: stretch`로 변경한다면 이 JS 로직이 필요 없을 수도 있으나, 썸네일 이미지 비율이 깨질 위험이 있음. 현재의 JS 제어 방식이 가장 안전함.
3.  **패딩 수정 시:** JS 코드 내 `LIST_TOP_PADDING`과 `LIST_BOTTOM_PADDING` 상수를 함께 수정해야 계산이 틀어지지 않음.

---