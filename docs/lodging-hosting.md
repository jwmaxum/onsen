# 숙박업소 검수 DB와 Firebase 미리보기

2026년 11월 20일 검수 배치는 지역별 상세 36곳과 도미인 국내 목록 103곳, 유후인 표본 10곳을 포함한다. 상세와 도미인 목록의 지점 ID 8개를 한 건으로 묶어 **141건**의 사적 검수 자료를 등록했다. 기존 카탈로그 식별자는 같은 도도부현·시정촌에서 슬러그나 정규화 명칭이 유일하게 일치할 때 연결한다. 나머지 숙소는 근거와 검수 작업을 남긴다.

유후인온천(由布院温泉)은 환경성 계획의 온천향(湯布院温泉郷)을 구성하는 개별 온천지다. 2026년 5월 1일 오이타현 숙박업 허가 자료와 운영사 표본을 대조해 가메노이 벳소, 다마노유, 산소 무라타, 카이 유후인, 소안 코스모스, 료테이 다노쿠라, 사이가쿠칸, 무소엔, 쓰카노마, 산스이칸을 연결했다. 허가의 기준일과 운영사 자료 확인일을 보존한다. 허가 원장의 유후시 445행에는 여러 온천지와 온천이 없는 시설이 포함된다. [환경성 온천향 계획](https://www.env.go.jp/nature/onsen/area/pdf/hoyo_067.pdf) · [유후시 온천 안내](https://www.city.yufu.oita.jp/kankou/onsen) · [오이타현 숙박업 허가 목록](https://www.pref.oita.jp/soshiki/13900/ryokangyo-zyutakusisetsu.html)

## 검수 배치 재현

검토 자료는 작업 환경에서 관리하며 GitHub와 Firebase에는 포함하지 않는다. `ingest/lodging_catalog_batch.py`에 지역·도미인·유후인 검수 JSON의 경로를 각각 `--region`, `--directory`, `--yufuin`으로 전달한다. 기본 실행은 검증만 수행한다. 로컬 관리자 `ONSEN_LOCAL_DSN`을 설정한 후 `--apply`로 적용한다. 모든 후보는 `ingest.external_records`와 출처 연결 관측에 적재되며 유후인 표본은 `core.area_facilities`의 초안에 연결된다. 원본 재배포나 공개 좌표와 사진 사용 조건은 채널별로 검수한다.

전용 PostgreSQL에서 배치를 두 번 실행해 후보·관측·검수 작업 141건과 유후인 연결 10건을 확인했다. 공개 카탈로그 지문이 동일했고 익명 역할의 비공개 `ingest` 스키마 접근은 거부됐다. 앱의 PostgreSQL 읽기 경로에 변경이 없으며 미리보기 배포물에는 비공개 자료가 들어가지 않는다.

## Firebase 정적 미리보기

로컬 PostgREST와 Next.js를 준비한 뒤 `python -m pip install -r scripts/hosting-requirements.txt`를 실행한다. `python scripts/build-firebase-preview.py --origin http://127.0.0.1:55449`는 승인된 현재 릴리스와 네 언어 상세·조사 현황 화면을 한정된 로컬 요청으로 읽어 `.firebase-preview`에 저장한다. 이전 스냅샷이 있으면 이동한 뒤 새 스냅샷을 만든다. 집계나 숙소 정보 변경 후에는 다시 생성해 배포한다.

```powershell
npm exec --yes --package=firebase-tools -- firebase hosting:channel:deploy onsen-review --project onsen-587dc --expires 30d
```

정적 화면에서 언어 전환, 목록·상세 이동, 지도, 조사 현황을 볼 수 있다. 실시간 필터·페이지 추가 및 Analytics 초기화는 로컬 Next.js 앱의 기능이다. 외부 서버에서 실시간 DB 조회를 하려면 접근 제어가 적용된 운영 데이터 API와 SSR 호스팅을 설정한다. [Firebase 미리보기 채널](https://firebase.google.com/docs/hosting/test-preview-deploy)

## Cloudflare의 Firebase 카탈로그

Cloudflare Worker는 `ONSEN_FIREBASE_DATABASE_URL`의 Realtime Database에서 `/onsen_public/v1.json`을 읽는다. 공개 API의 여섯 뷰를 JSON 문자열로 저장해 빈 배열과 `null`을 유지한다. Worker는 조회 결과를 최대 60초 동안 재사용한다. DB 규칙은 이 경로에 익명 읽기를 허용하고 모든 클라이언트 쓰기를 거부한다. `ONSEN_CURSOR_SECRET`은 Worker의 런타임 비밀값에 저장한다. [Firebase REST 조회](https://firebase.google.com/docs/database/rest/retrieve-data) · [Realtime Database 규칙](https://firebase.google.com/docs/database/security)

### 검수 후 자동 발행

검수 담당자가 원본 DB에서 릴리스를 활성화하면 Windows 발행 작업이 익명 PostgREST의 공개 뷰 여섯 개를 읽는다. 현황이나 분석이 바뀌면 같은 릴리스 ID에서도 반영한다. Firebase에서는 ETag가 일치할 때 공개 경로 하나를 한 번에 교체하고 읽어서 확인한다. 다른 발행이 먼저 완료되면 다음 실행에서 최신 데이터를 다시 대조한다. [조건부 쓰기](https://firebase.google.com/docs/database/rest/save-data#section-conditional-requests)

Firebase Authentication에서 발행에 사용할 익명 인증을 활성화한 뒤 `scripts/sync-firebase-catalog.ps1 -InitializePublisher`를 발행 Windows 계정에서 한 번 실행한다. 반환된 UID만 `/onsen_public/v1`에 `auth != null && auth.uid === '<UID>' && newData.isString()` 조건으로 쓰기 허용한다. 발행 세션은 해당 Windows 계정의 DPAPI로 보호하며 `.wrangler/firebase-publisher`에 둔다. [Firebase 인증과 규칙](https://firebase.google.com/docs/database/security/rules-conditions)

```powershell
./scripts/sync-firebase-catalog.ps1
./scripts/sync-firebase-catalog.ps1 -RegisterTask
```

첫 명령으로 쓰기 또는 변경 없음 결과를 확인한 뒤 작업을 등록한다. 작업은 같은 Windows 계정이 로그인하고 로컬 PostgREST가 실행 중일 때 매분 확인한다. `.wrangler/firebase-publisher/last-run.json`에 마지막 결과를 남긴다. Worker의 최대 60초 캐시가 만료되면 목록과 API에 반영된다. GitHub `main` 푸시는 Workers 앱 코드 배포를 시작한다.

### 초기화와 수동 복구

공개 데이터의 복구 파일이 필요하면 익명 PostgREST 주소로 생성한다.

```powershell
node scripts/export-firebase-catalog.mjs http://127.0.0.1:55450 .wrangler/onsen-catalog-new.json
```

Firebase 콘솔에서 `/onsen_public`으로 이동해 내보낸 파일의 `onsen_public` 객체를 가져온다. 루트 가져오기는 빈 DB를 초기화할 때 사용한다. 공개 경로의 릴리스 ID와 항목 수를 Cloudflare 목록 및 API와 대조한다.

## 공간 격자 조사

200m 격자는 시정촌 내에서 조사한 구역과 미확인 구역을 표시하는 데 사용한다. 허가 원장과 지자체가 공개한 온천 시설을 우선 찾고, 좌표 사용 조건을 확인한 자료만 미터 단위 투영 좌표계에서 격자에 매핑한다. 유후인에서는 온천지 경계 또는 시설 밀집 구역에서 시작하고, 후보·근거·검수 결과를 셀 단위로 기록한다. 출처 ID와 주소로 중복을 줄이고 운영사 자료로 숙박과 자연온천을 확인한다. 행정 원장에 없는 후보는 발견 근거를 남겨 별도 검수한다.

일본 전체를 고정 200m 셀로 조사하면 육지 면적만 거칠게 나눠도 약 950만 개다. 산지·해역 주변의 빈 셀이 늘어나고, 같은 시설은 인접 셀에서 중복되며, 검색 결과 상한과 순위 때문에 반환 결과만으로 전수를 확인할 수 없다. Google Places 검색 결과의 반출·저장에는 별도 조건이 있으므로 전국 온천 DB의 원장으로 사용하지 않는다. 격자는 공개 원장 대조에서 공백을 발견했을 때 조사 작업을 나누는 방식으로 사용한다. [Google Maps Platform 이용 조건](https://cloud.google.com/maps-platform/terms) · [Nearby Search 결과 조건](https://developers.google.com/maps/documentation/places/web-service/nearby-search)
