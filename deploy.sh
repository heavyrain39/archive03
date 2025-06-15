#!/bin/bash

echo -e "\033[0;32mDeploying updates to GitHub...\033[0m"

# 1. 사이트를 빌드합니다. (hugo 명령어)
hugo # -t <theme_name> # 테마를 쓴다면 이 주석을 해제하세요.

# 2. 빌드된 public 폴더로 이동합니다.
cd public

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
git push -f git@github.com:heavyrain39/archive03.git main:gh-pages

# 6. 원래 폴더로 돌아옵니다.
cd ..