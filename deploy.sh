#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

readonly BASE_URL="https://archive03.online/"

# 1. 사이트를 빌드합니다.
echo "Building site with Hugo..."
hugo -b "$BASE_URL"

# 2. 빌드된 public 폴더로 이동합니다.
cd public || { echo "Hugo build failed. 'public' directory not found."; exit 1; }

# 3. 이 폴더를 Git 저장소로 만들고, 변경사항을 추가합니다.
git init
git add .

# 4. 커밋 메시지를 작성합니다.
msg="rebuilding site $(date)"
if [ -n "$*" ]; then
    msg="$*"
fi
git commit -m "$msg"

# 5. gh-pages 브랜치로 강제 푸시합니다.
# [수정] 'main' 대신 'HEAD'를 사용합니다.
# HEAD는 현재 작업 중인 브랜치를 가리키는 포인터이므로,
# 기본 브랜치 이름이 main이든 master든 상관없이 항상 올바르게 작동합니다.
echo "Pushing to gh-pages branch..."
git push -f git@github.com:heavyrain39/archive03.git HEAD:gh-pages

# 6. 푸시 성공 여부를 확인하고 원래 폴더로 돌아갑니다.
if [ $? -eq 0 ]; then
    cd ..
    echo -e "\033[0;32mDeployment successful! ✅\033[0m"
else
    cd ..
    echo -e "\033[0;31mDeployment failed. ❌\033[0m"
    exit 1
fi