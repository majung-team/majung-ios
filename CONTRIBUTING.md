# 기여 가이드

처음 clone한 뒤 Node.js 22 이상으로 다음 명령을 실행하면 로컬 커밋 검사가 설정됩니다.

```sh
npm ci
git config --local commit.template .gitmessage
```

커밋과 PR 제목은 `type(scope): 변경 내용`으로 작성합니다. 예를 들어 `feat(ios): 받은 초대 목록 추가`처럼 적습니다. scope는 생략할 수 있습니다. 제목은 72자 이내로 쓰고 마침표와 이슈 번호는 붙이지 않습니다.

- type은 `feat`, `fix`, `refactor`, `test`, `docs`, `style`, `build`, `ci`, `chore`, `revert`를 사용합니다.
- scope는 `ios`, `repo`, `ci`, `deps`를 사용합니다.

기능 추가나 오류 수정은 관련 이슈를 확인한 뒤 `main`에서 작업 브랜치를 만듭니다. 브랜치 이름은 `feat/12-invite-list`처럼 씁니다. PR 본문에 바꾼 동작과 실제 확인한 내용을 적고, 이슈는 `Refs: #12` 또는 `Closes: #12`로 연결합니다. 화면이 바뀌면 캡처를 첨부합니다. 병합은 squash merge를 기본으로 합니다.

GitHub Actions는 PR 제목과 브랜치의 커밋 제목을 검사하고, PR과 `main`에서 시뮬레이터 빌드를 확인합니다.
