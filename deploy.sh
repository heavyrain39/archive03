#!/bin/bash

# ==============================================================================
# Archive 03: 자동 배포 스크립트 (v2.1 - 증분 업데이트 버전)
# ==============================================================================

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Step 1: Hugo로 사이트를 빌드합니다.
# 빌드된 결과물은 이미 'gh-pages' 브랜치의 복사본인 'public' 폴더 안으로 들어갑니다.
echo "Building site with Hugo..."
hugo

# Step 2: 배포 폴더(서브모듈)로 이동합니다.
cd public || { echo "'public' directory not found. Did you run the one-time setup?"; exit 1; }

# Step 3: 변경된 모든 파일 (추가, 수정, 삭제)을 스테이징합니다.
git add .

# Step 4: 커밋 메시지를 작성합니다. 기본 메시지 또는 인자로 받은 메시지를 사용합니다.
msg="rebuilding site $(date)"
if [ -n "$*" ]; then
    msg="$*"
fi

# 변경 사항이 있을 때만 커밋을 진행합니다.
if git diff-index --quiet HEAD; then
    echo "No changes to commit. Everything is up to date."
else
    git commit -m "$msg"
    # Step 5: 'gh-pages' 브랜치로 변경사항을 푸시합니다. '-f' 옵션이 필요 없습니다.
    echo "Pushing updates to gh-pages branch..."
    git push origin gh-pages
fi

# Step 6: 메인 프로젝트 폴더로 돌아옵니다.
cd ..

# Step 7: [선택 사항] 메인 프로젝트에 서브모듈의 변경사항을 기록합니다.
# 이 과정을 통해, 메인 브랜치는 항상 어떤 버전의 사이트가 배포되었는지 알 수 있습니다.
git add public
git commit -m "Update public submodule to latest commit"
git push

echo -e "\033[0;32mDeployment successful! ✅\033[0m"