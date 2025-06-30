#!/bin/bash

# ==============================================================================
# Archive 03: 자동 배포 스크립트 (v2.2 - 안정성 개선 버전)
# ==============================================================================

# 스크립트 실행 중 오류가 발생하면 즉시 중단합니다.
set -e

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# Step 1: Hugo로 사이트를 빌드합니다.
# 빌드된 결과물은 이미 'gh-pages' 브랜치의 복사본인 'public' 폴더 안으로 들어갑니다.
echo "Building site with Hugo..."
hugo --cleanDestinationDir --minify # --minify 플래그를 추가하여 빌드 결과물을 압축합니다.

# Step 2: 배포 폴더(서브모듈)로 이동합니다.
cd public || { echo "'public' directory not found. Exiting."; exit 1; }

# Step 3: 변경 사항이 있는지 확인하고, 없다면 스크립트를 종료합니다.
if [[ -z $(git status -s) ]]; then
    echo "No changes to deploy in 'public' directory."
    cd ..
    echo -e "\033[0;33mDeployment skipped. No new content to publish. ⚠️\033[0m"
    exit 0
fi

# Step 4: 변경된 모든 파일 (추가, 수정, 삭제)을 스테이징하고 커밋합니다.
echo "Adding changes to gh-pages..."
git add .

msg="rebuilding site $(date)"
if [ -n "$*" ]; then
    msg="$*"
fi
git commit -m "$msg"

# Step 5: 'gh-pages' 브랜치로 변경사항을 푸시합니다.
echo "Pushing updates to gh-pages branch..."
# 'origin'이라는 별명 대신, 전체 원격 저장소 URL을 명시적으로 사용합니다.
# 이는 서브모듈의 로컬 설정에 의존하지 않으므로 더 안정적입니다.
git push git@github.com:heavyrain39/archive03.git HEAD:gh-pages

# Step 6: 메인 프로젝트 폴더로 돌아옵니다.
cd ..

# Step 7: 메인 프로젝트에 서브모듈의 변경사항을 기록하고 푸시합니다.
echo "Updating submodule reference in main branch..."
git add public
git commit -m "Update public submodule to latest commit"
git push

echo -e "\033[0;32mDeployment successful! ✅\033[0m"