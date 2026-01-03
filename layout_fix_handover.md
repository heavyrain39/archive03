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
