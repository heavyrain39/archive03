#!/bin/bash

# ==============================================================================
# Archive 03: 자동 배포 스크립트 (v2.0 - 자동 클린업 기능 탑재)
# ==============================================================================

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

readonly BASE_URL="https://archive03.online/"

# [핵심 수정!] Step 0: 기존 빌드 폴더(public)를 깨끗하게 삭제합니다.
# 이 과정을 통해, 로컬에서 삭제된 파일이 배포 브랜치에 유령처럼 남는 문제를
# 근본적으로 해결합니다. "일단 비우고, 새로 채운다!"
echo "Cleaning up old build..."
rm -rf public

# Step 1: 깨끗한 상태에서 사이트를 새로 빌드합니다.
echo "Building site with Hugo..."
hugo -b "$BASE_URL"

# Step 2: 빌드된 public 폴더로 이동합니다.
cd public || { echo "Hugo build failed. 'public' directory not found."; exit 1; }

# Step 3: 이 폴더를 Git 저장소로 만들고, 변경사항을 추가합니다.
git init
git add .

# Step 4: 커밋 메시지를 작성합니다.
msg="rebuilding site $(date)"
if [ -n "$*" ]; then
    msg="$*"
fi
git commit -m "$msg"

# Step 5: gh-pages 브랜치로 강제 푸시합니다.
echo "Pushing to gh-pages branch..."
git push -f git@github.com:heavyrain39/archive03.git HEAD:gh-pages

# Step 6: 푸시 성공 여부를 확인하고 원래 폴더로 돌아갑니다.
if [ $? -eq 0 ]; then
    cd ..
    echo -e "\033[0;32mDeployment successful! ✅\033[0m"
else
    cd ..
    echo -e "\033[0;31mDeployment failed. ❌\033[0m"
    exit 1
fi