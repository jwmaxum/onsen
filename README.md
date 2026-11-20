# Onsen Atlas

일본 온천 시설을 북쪽부터 볼 수 있는 한국어·일본어·영어·중국어 간체 사이트입니다. Next.js와 Supabase/PostGIS를 사용합니다.

1. Node.js 24에서 `npm ci`를 실행합니다.
2. `.env.example`을 `.env.local`로 복사하고 로컬 Supabase 또는 PostgREST URL과 서버용 커서 서명 값을 설정합니다.
3. 로컬 Supabase를 시작하고 마이그레이션을 적용합니다. 공개 승인 데이터는 검수 절차에 따라 적재합니다. 초기 합성 표본은 개발 검증용입니다.
4. `npm run dev -- --hostname 127.0.0.1`을 실행한 뒤 `/ko/onsen`을 엽니다.

숙박 데이터 검수 배치, 유후인 조사와 Firebase 미리보기는 [운영 문서](docs/lodging-hosting.md)를 참고하세요. 검수 중인 데이터와 개인 환경 파일은 로컬에서 관리합니다.
