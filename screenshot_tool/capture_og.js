const { chromium } = require('playwright-chromium');
const path = require('path');
const fs = require('fs');

(async () => {
  console.log('Playwright 실행 중...');
  let browser;
  try {
    browser = await chromium.launch({ 
      headless: true,
      args: ['--no-sandbox', '--disable-setuid-sandbox'] 
    });
    const page = await browser.newPage();
    
    // OG 표준 사이즈 (1.91:1) 설정
    await page.setViewportSize({ width: 1200, height: 630 });
    
    console.log('http://localhost:1313 접속 중...');
    await page.goto('http://localhost:1313', { 
      waitUntil: 'networkidle',
      timeout: 30000 
    });
    
    // 폰트 및 레이아웃 안정화를 위해 잠시 대기
    await page.waitForTimeout(2000);
    
    // 저장 경로 설정 (assets/images/og-default.png)
    const outputPath = path.resolve(__dirname, '..', 'assets', 'images', 'og-default.png');
    const dir = path.dirname(outputPath);
    
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
      console.log(`디렉토리 생성됨: ${dir}`);
    }
    
    console.log(`스크린샷 저장 중: ${outputPath}`);
    await page.screenshot({ 
      path: outputPath,
      fullPage: false // 뷰포트 크기인 1200x630만 캡처 (상단 부분)
    });
    
    console.log('성공적으로 캡처되었습니다.');
  } catch (error) {
    console.error('캡처 중 오류 발생:', error);
    process.exit(1);
  } finally {
    if (browser) await browser.close();
  }
})();
