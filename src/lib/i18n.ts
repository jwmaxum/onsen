import { createTranslator } from 'next-intl';
import { localeLabels, type Locale } from './catalog-query';
import type { Entry } from './catalog-types';

const ko = {
  brand: '온센 아틀라스', skip: '본문으로 건너뛰기', language: '언어 선택', home: '온천 탐색',
  headline1: '일본 온천을', headline2: '북쪽에서 남쪽으로', intro: '홋카이도 왓카나이에서 규슈 벳푸까지. 공식 자료를 바탕으로 확인한 온천과 이동 경로를 위도순으로 탐색하세요.',
  sample: '검수 표본', catalog: '공개 목록', journey: '홋카이도 → 규슈', nationwide: '전국', facilities: '시설', areas: '온천지',
  region: '지역', allRegions: '전체 지역', quality: '천질', allQualities: '전체 천질', price: '당일 입욕료 상한 (JPY)',
  apply: '필터 적용', reset: '필터 초기화', results: '위도순 온천 목록', northSouth: '북쪽 → 남쪽', count: '표시 중 {count}곳',
  noResults: '선택한 조건에 맞는 공개 기록이 없습니다.', priceRule: '가격 필터는 검수된 당일 입욕료가 있는 시설에 적용됩니다.',
  more: '더 보기', loading: '불러오는 중', unavailable: '공개 데이터를 불러오지 못했습니다.', retry: '목록 다시 열기',
  badQuery: '검색 조건이나 목록 링크를 확인해 주세요.', expired: '목록 버전이 갱신되었습니다. 목록을 다시 열어 주세요.',
  mapTitle: '열도 위의 온천', mapNote: '현재 목록의 시설 대표 좌표', mapCredit: '지도 데이터 Natural Earth',
  view: '시설 상세 보기', areaView: '온천지 상세 보기', original: '일본어 원문', back: '목록으로', prev: '이전 · 북쪽', next: '다음 · 남쪽',
  address: '일본어 주소', copy: '주소 복사', copied: '복사됨', copyFail: '주소를 선택해 복사해 주세요',
  overview: '시설 정보', rooms: '객실', baths: '온천탕', admission: '당일 입욕료', pending: '확인 중', verified: '확인일', source: '공식 출처',
  noPhoto: '공개 승인된 사진이 확인되면 표시됩니다.', representative: '표시 좌표는 시설 또는 주소의 대표 위치입니다.',
  analyses: '검수된 원천 분석', analysisNote: '시료별 분석 결과와 원문 출처입니다.', noAnalysis: '공개 검수를 마친 분석 자료를 준비 중입니다.',
  temperature: '원천 온도', fieldPh: '현장 pH', labPh: '실험실 pH', sampled: '채수일', analyzed: '분석일', accessed: '이용일',
  terms: '이용규약', processed: '가공 표기', transport: '거점에서 온천까지', transportNote: '승하차 위치와 이동 구간을 확인하세요.',
  noRoute: '공개 검수를 마친 이동 경로를 준비 중입니다.', walk: '도보', bus: '버스', minutes: '{minutes}분',
  total: '전체 시간', fare: '편도 운임', transfers: '환승 {count}회', routeSource: '경로 근거', legSource: '구간 근거',
  validUntil: '피드 유효기간', reservationYes: '예약 필요', reservationNo: '예약 불필요',
  footer: '일본 온천의 공개 자료를 모아 위치와 교통을 함께 안내합니다.', noAreas: '검수된 온천지 기록을 준비 중입니다.',
};

type Messages = Record<keyof typeof ko, string>;
const messages: Record<Locale, Messages> = {
  ko,
  ja: {
    brand: '温泉アトラス', skip: '本文へ移動', language: '言語を選択', home: '温泉を探す',
    headline1: '日本の温泉を', headline2: '北から南へ', intro: '北海道の稚内から九州の別府まで。公式資料で確認した温泉とアクセスを、緯度順にたどります。',
    sample: '確認済みのサンプル', catalog: '公開リスト', journey: '北海道 → 九州', nationwide: '全国', facilities: '施設', areas: '温泉地',
    region: '地域', allRegions: 'すべての地域', quality: '泉質', allQualities: 'すべての泉質', price: '日帰り入浴料の上限（JPY）',
    apply: '絞り込む', reset: '条件をクリア', results: '緯度順の温泉リスト', northSouth: '北 → 南', count: '{count}件を表示',
    noResults: '選択した条件に該当する公開情報はありません。', priceRule: '確認済みの日帰り入浴料がある施設に適用します。',
    more: 'さらに表示', loading: '読み込み中', unavailable: '公開データを読み込めませんでした。', retry: 'リストを開き直す',
    badQuery: '検索条件またはリストのリンクを確認してください。', expired: 'リストが更新されました。開き直してください。',
    mapTitle: '列島の温泉', mapNote: '表示中の施設の代表座標', mapCredit: '地図データ Natural Earth',
    view: '施設の詳細', areaView: '温泉地の詳細', original: '日本語原文', back: 'リストへ戻る', prev: '前へ · 北', next: '次へ · 南',
    address: '日本語の住所', copy: '住所をコピー', copied: 'コピーしました', copyFail: '住所を選択してコピーしてください',
    overview: '施設情報', rooms: '客室', baths: '浴槽', admission: '日帰り入浴料', pending: '確認中', verified: '確認日', source: '公式資料',
    noPhoto: '公開承認済みの写真が確認でき次第表示します。', representative: '表示座標は施設または住所の代表点です。',
    analyses: '確認済みの源泉分析', analysisNote: '試料別の分析結果と原本です。', noAnalysis: '公開確認を終えた分析資料を準備しています。',
    temperature: '源泉温度', fieldPh: '現地 pH', labPh: '試験室 pH', sampled: '採水日', analyzed: '分析日', accessed: '利用日',
    terms: '利用規約', processed: '加工表示', transport: '拠点から温泉まで', transportNote: '乗降場所と移動区間をご確認ください。',
    noRoute: '公開確認済みの経路を準備しています。', walk: '徒歩', bus: 'バス', minutes: '{minutes}分',
    total: '全体の所要時間', fare: '片道運賃', transfers: '乗換 {count}回', routeSource: '経路の出典', legSource: '区間の出典',
    validUntil: 'データ有効期限', reservationYes: '予約が必要', reservationNo: '予約不要',
    footer: '日本の温泉を、公開資料の位置と交通情報から案内します。', noAreas: '確認済みの温泉地を準備しています。',
  },
  en: {
    brand: 'Onsen Atlas', skip: 'Skip to content', language: 'Choose a language', home: 'Explore onsen',
    headline1: 'Japan’s hot springs,', headline2: 'north to south', intro: 'From Wakkanai in Hokkaido to Beppu in Kyushu. Explore hot springs and directions checked against official sources, in latitude order.',
    sample: 'Reviewed pilot', catalog: 'Published catalogue', journey: 'Hokkaido → Kyushu', nationwide: 'Nationwide', facilities: 'Facilities', areas: 'Onsen areas',
    region: 'Region', allRegions: 'All regions', quality: 'Spring type', allQualities: 'All spring types', price: 'Max day admission (JPY)',
    apply: 'Apply filters', reset: 'Reset filters', results: 'Hot springs by latitude', northSouth: 'North → South', count: '{count} shown',
    noResults: 'No published records match these filters.', priceRule: 'The price filter includes facilities with a verified day admission fee.',
    more: 'Show more', loading: 'Loading', unavailable: 'Published data could not be loaded.', retry: 'Reopen the list',
    badQuery: 'Check the filters or the list link.', expired: 'The list was updated. Reopen it to continue.',
    mapTitle: 'Across the archipelago', mapNote: 'Reference points for facilities in this list', mapCredit: 'Map data Natural Earth',
    view: 'View facility', areaView: 'View onsen area', original: 'Japanese original', back: 'Back to list', prev: 'Previous · North', next: 'Next · South',
    address: 'Address in Japanese', copy: 'Copy address', copied: 'Copied', copyFail: 'Select the address to copy it',
    overview: 'Facility information', rooms: 'Rooms', baths: 'Baths', admission: 'Day admission', pending: 'Under review', verified: 'Verified on', source: 'Official source',
    noPhoto: 'Photos will appear once approved for publication.', representative: 'Coordinates mark a reference location for the facility or address.',
    analyses: 'Reviewed spring-water analyses', analysisNote: 'Measurements by sample, with the original reports.', noAnalysis: 'Analysis reports are awaiting publication review.',
    temperature: 'Source temperature', fieldPh: 'Field pH', labPh: 'Lab pH', sampled: 'Sampled on', analyzed: 'Analyzed on', accessed: 'Accessed on',
    terms: 'Terms of use', processed: 'Processing disclosure', transport: 'From the hub to the onsen', transportNote: 'Check the boarding points and each leg of the journey.',
    noRoute: 'Directions are awaiting publication review.', walk: 'Walk', bus: 'Bus', minutes: '{minutes} min',
    total: 'Total time', fare: 'One-way fare', transfers: '{count} transfers', routeSource: 'Route source', legSource: 'Leg source',
    validUntil: 'Feed valid through', reservationYes: 'Reservation required', reservationNo: 'Reservation unnecessary',
    footer: 'A guide to Japan’s hot springs with locations and transport from public sources.', noAreas: 'Onsen area records are awaiting publication review.',
  },
  'zh-Hans': {
    brand: '温泉图鉴', skip: '跳转到正文', language: '选择语言', home: '探索温泉',
    headline1: '日本温泉', headline2: '从北到南', intro: '从北海道稚内到九州别府，按纬度浏览经官方资料核对的温泉与交通路线。',
    sample: '已核查样本', catalog: '公开目录', journey: '北海道 → 九州', nationwide: '全国', facilities: '设施', areas: '温泉地区',
    region: '地区', allRegions: '所有地区', quality: '泉质', allQualities: '所有泉质', price: '当日入浴费上限（JPY）',
    apply: '应用筛选', reset: '重置筛选', results: '按纬度排列的温泉', northSouth: '北 → 南', count: '显示 {count} 处',
    noResults: '没有符合筛选条件的公开记录。', priceRule: '价格筛选仅适用于已核查当日入浴费的设施。',
    more: '显示更多', loading: '正在加载', unavailable: '暂时无法加载公开数据。', retry: '重新打开列表',
    badQuery: '请检查筛选条件或列表链接。', expired: '列表已更新，请重新打开。',
    mapTitle: '列岛上的温泉', mapNote: '当前列表设施的参考坐标', mapCredit: '地图数据 Natural Earth',
    view: '查看设施', areaView: '查看温泉地区', original: '日语原文', back: '返回列表', prev: '上一处 · 北', next: '下一处 · 南',
    address: '日语地址', copy: '复制地址', copied: '已复制', copyFail: '请选择地址后复制',
    overview: '设施信息', rooms: '客房', baths: '浴池', admission: '当日入浴费', pending: '核查中', verified: '核查日期', source: '官方来源',
    noPhoto: '照片通过公开审核后将显示。', representative: '坐标为设施或地址的参考位置。',
    analyses: '已核查的源泉分析', analysisNote: '各样本的测量结果和原始报告。', noAnalysis: '分析资料正在进行公开审核。',
    temperature: '源泉温度', fieldPh: '现场 pH', labPh: '实验室 pH', sampled: '采样日期', analyzed: '分析日期', accessed: '访问日期',
    terms: '使用条款', processed: '加工说明', transport: '从交通枢纽到温泉', transportNote: '请确认上下车地点和各路段。',
    noRoute: '路线正在进行公开审核。', walk: '步行', bus: '公交车', minutes: '{minutes} 分钟',
    total: '总耗时', fare: '单程车费', transfers: '换乘 {count} 次', routeSource: '路线来源', legSource: '路段来源',
    validUntil: '数据有效期至', reservationYes: '需预约', reservationNo: '无需预约',
    footer: '整理日本温泉的公开资料，提供位置与交通信息。', noAreas: '温泉地区记录正在进行公开审核。',
  },
};

export function text(locale: Locale) {
  return createTranslator({ locale, messages: messages[locale], timeZone: 'Asia/Tokyo' });
}

const names: Record<string, Record<Locale, string>> = {
  'wakkanai-onsen-domu': { ko: '왓카나이 온천 도무', ja: '稚内温泉童夢', en: 'Wakkanai Onsen Dōmu', 'zh-Hans': '稚内温泉童梦' },
  'daiichi-takimotokan': { ko: '다이이치 타키모토칸', ja: '第一滝本館', en: 'Dai-ichi Takimotokan', 'zh-Hans': '第一泷本馆' },
  'takegawara-onsen': { ko: '다케가와라 온천', ja: '竹瓦温泉', en: 'Takegawara Onsen', 'zh-Hans': '竹瓦温泉' },
  'rebun-usuyuki-no-yu': { ko: '레분섬 온천 우스유키노유', ja: '礼文島温泉うすゆきの湯', en: 'Rebun Island Onsen Usuyuki no Yu', 'zh-Hans': '礼文岛温泉薄雪之汤' },
  'wakkanai-minato-no-yu': { ko: '왓카나이 미나토노유', ja: 'ヤムワッカナイ温泉 港のゆ', en: 'Wakkanai Minato no Yu', 'zh-Hans': '稚内港之汤' },
  'rishiri-fureai-onsen': { ko: '리시리 후레아이 온천', ja: '利尻ふれあい温泉', en: 'Rishiri Fureai Onsen', 'zh-Hans': '利尻交流温泉' },
  'hirakawa-fukuya': { ko: '쓰가루 오노에 온천 후쿠야', ja: '津軽おのえ温泉 日帰りの宿 福家', en: 'Tsugaru Onoe Onsen Fukuya', 'zh-Hans': '津轻尾上温泉福家' },
  'ikarigaseki-okariya-goten': { ko: '이카리가세키 오카리야고텐', ja: '平川市温泉交流館 御仮屋御殿', en: 'Ikarigaseki Okariya Goten', 'zh-Hans': '碇关御假屋御殿' },
  'sendai-seaside-kaijin-no-yu': { ko: '센다이 시사이드 가이진노유', ja: '天然温泉 海神の湯 ドーミーインEXPRESS仙台シーサイド', en: 'Kaijin no Yu at Dormy Inn Sendai Seaside', 'zh-Hans': '多美迎仙台海滨海神之汤' },
};

export function entryName(entry: Entry, locale: Locale) { return names[entry.slug]?.[locale] ?? entry.name_ja; }
export function entryLanguage(entry: Entry, locale: Locale) { return names[entry.slug] ? locale : 'ja'; }
export function hasLocalizedEntry(entry: Entry) { return Boolean(names[entry.slug]); }

const introductions: Record<string, Record<Locale, string>> = {
  'wakkanai-minato-no-yu': {
    ko: '왓카나이 후코 시장 2층에 있는 당일 입욕 온천입니다.',
    ja: '稚内副港市場の2階にある日帰り入浴施設です。',
    en: 'A day-use hot spring on the second floor of Wakkanai Fukuko Market.',
    'zh-Hans': '位于稚内副港市场二楼的日归温泉。',
  },
  'rebun-usuyuki-no-yu': {
    ko: '홋카이도 레분섬의 공중 온천입니다.',
    ja: '北海道の礼文島にある公共温泉です。',
    en: 'A public hot spring on Rebun Island, Hokkaido.',
    'zh-Hans': '位于北海道礼文岛的公共温泉。',
  },
  'rishiri-fureai-onsen': {
    ko: '리시리섬 서쪽 구쓰가타에 있는 당일 입욕 온천입니다.',
    ja: '利尻島西部の沓形にある日帰り入浴施設です。',
    en: 'A day-use hot spring in Kutsugata, on the west side of Rishiri Island.',
    'zh-Hans': '位于利尻岛西部沓形的日归温泉。',
  },
  'wakkanai-onsen-domu': {
    ko: '홋카이도 왓카나이의 공공 입욕 시설입니다. JR 왓카나이역 앞 터미널에서 소야버스로 갈 수 있습니다.',
    ja: '北海道稚内市の入浴施設です。JR稚内駅前のターミナルから宗谷バスでアクセスできます。',
    en: 'A public bathing facility in Wakkanai, Hokkaido, reached by Soya Bus from the terminal by JR Wakkanai Station.',
    'zh-Hans': '位于北海道稚内市的公共入浴设施，可从 JR 稚内站前总站乘坐宗谷巴士前往。',
  },
  'daiichi-takimotokan': {
    ko: '홋카이도 노보리베츠 온천 지구의 료칸입니다. JR 노보리베츠역에서 도난버스로 연결됩니다.',
    ja: '北海道の登別温泉にある旅館です。JR登別駅から道南バスでアクセスできます。',
    en: 'A ryokan in the Noboribetsu Onsen district of Hokkaido, served by Donan Bus from JR Noboribetsu Station.',
    'zh-Hans': '位于北海道登别温泉地区的日式旅馆，可从 JR 登别站乘坐道南巴士前往。',
  },
  'takegawara-onsen': {
    ko: '벳푸시의 시영 온천입니다. JR 벳푸역에서 역 앞 거리를 따라 걸어서 갈 수 있습니다.',
    ja: '別府市の市営温泉です。JR別府駅から駅前通りを歩いてアクセスできます。',
    en: 'A municipal hot spring in Beppu. Walk from JR Beppu Station along Ekimae-dori.',
    'zh-Hans': '别府市经营的温泉，可从 JR 别府站沿站前通步行前往。',
  },
};

export function entryIntroduction(entry: Entry, locale: Locale) { return introductions[entry.slug]?.[locale]; }

const regions: Record<string, Record<Locale, string>> = {
  '01': { ko: '홋카이도', ja: '北海道', en: 'Hokkaido', 'zh-Hans': '北海道' },
  '02': { ko: '아오모리현', ja: '青森県', en: 'Aomori', 'zh-Hans': '青森县' },
  '04': { ko: '미야기현', ja: '宮城県', en: 'Miyagi', 'zh-Hans': '宫城县' },
  '44': { ko: '오이타현', ja: '大分県', en: 'Oita', 'zh-Hans': '大分县' },
};
export function regionName(code: string, locale: Locale) { return regions[code]?.[locale] ?? `JP-${code}`; }

const qualityNames = {
  ko: ['단순온천', '염화물천', '탄산수소염천', '황산염천', '이산화탄소천', '함철천', '산성천', '함요오드천', '유황천', '방사능천'],
  ja: ['単純温泉', '塩化物泉', '炭酸水素塩泉', '硫酸塩泉', '二酸化炭素泉', '含鉄泉', '酸性泉', '含よう素泉', '硫黄泉', '放射能泉'],
  en: ['Simple spring', 'Chloride spring', 'Bicarbonate spring', 'Sulfate spring', 'Carbon dioxide spring', 'Iron spring', 'Acidic spring', 'Iodine spring', 'Sulfur spring', 'Radioactive spring'],
  'zh-Hans': ['单纯温泉', '氯化物泉', '碳酸氢盐泉', '硫酸盐泉', '二氧化碳泉', '含铁泉', '酸性泉', '含碘泉', '硫磺泉', '放射能泉'],
};

export { localeLabels, qualityNames };

const stopLabels: Record<string, Partial<Record<Locale, string>>> = {
  WAKKANAI_JR: { ko: 'JR 왓카나이역', en: 'JR Wakkanai Station', 'zh-Hans': 'JR 稚内站' },
  WAKKANAI_TERMINAL: { ko: '왓카나이역 앞 터미널', en: 'Wakkanai Station bus terminal', 'zh-Hans': '稚内站前公交总站' },
  WAKKANAI_DOMU_STOP: { ko: '왓카나이 온천 앞', en: 'Wakkanai Onsen-mae', 'zh-Hans': '稚内温泉前' },
  WAKKANAI_DOMU_ACCESS: names['wakkanai-onsen-domu'],
  NOBORIBETSU_JR: { ko: 'JR 노보리베츠역', en: 'JR Noboribetsu Station', 'zh-Hans': 'JR 登别站' },
  NOBORIBETSU_N1: { ko: '노보리베츠역 앞 (N1)', en: 'Noboribetsu Station stop (N1)', 'zh-Hans': '登别站前（N1）' },
  TAKIMOTO_N13: { ko: '다이이치 타키모토 앞 (N13)', en: 'Daiichi Takimoto-mae (N13)', 'zh-Hans': '第一泷本前（N13）' },
  TAKIMOTOKAN_ACCESS: names['daiichi-takimotokan'],
  BEPPU_JR: { ko: 'JR 벳푸역', en: 'JR Beppu Station', 'zh-Hans': 'JR 别府站' },
  BEPPU_EAST_5: { ko: '벳푸역 동쪽 출구 5번', en: 'Beppu Station East Exit, platform 5', 'zh-Hans': '别府站东口 5 号站台' },
  BEPPU_NAGAREKAWA: { ko: '나가레카와 유메타운 앞', en: 'Nagarekawa Youme Town-mae', 'zh-Hans': '流川 Youme Town 前' },
  TAKEGAWARA_ACCESS: names['takegawara-onsen'],
};

export function stopLabel(code: string, original: string, locale: Locale) {
  return stopLabels[code]?.[locale] ?? original;
}

const routeLabels: Record<string, Record<Locale, string>> = {
  'wakkanai-domu-transit': { ko: '왓카나이역 · 소야버스', ja: '稚内駅 · 宗谷バス', en: 'Wakkanai Station · Soya Bus', 'zh-Hans': '稚内站 · 宗谷巴士' },
  'noboribetsu-takimotokan-transit': { ko: '노보리베츠역 · 도난버스', ja: '登別駅 · 道南バス', en: 'Noboribetsu Station · Donan Bus', 'zh-Hans': '登别站 · 道南巴士' },
  'beppu-takegawara-walk': { ko: '벳푸역에서 도보', ja: '別府駅から徒歩', en: 'Walk from Beppu Station', 'zh-Hans': '从别府站步行' },
  'beppu-takegawara-bus16': { ko: '벳푸역 동쪽 출구 · 가메노이 16번', ja: '別府駅東口 · 亀の井バス16番', en: 'Beppu Station East Exit · Kamenoi bus 16', 'zh-Hans': '别府站东口 · 龟之井巴士 16 路' },
};

const routeNotes: Record<string, Record<Locale, string>> = {
  'wakkanai-domu-transit': {
    ko: '평일과 토·일·공휴일의 시간표가 다릅니다. 출발 전에 해당 날짜의 편을 확인하세요.',
    ja: '平日と土日祝で時刻表が異なります。ご利用日の便をご確認ください。',
    en: 'Weekday and weekend or holiday timetables differ. Check departures for your travel date.',
    'zh-Hans': '工作日和周末、节假日的时刻表不同，请查询出行当日的班次。',
  },
  'noboribetsu-takimotokan-transit': {
    ko: '첫 정류장부터 第一滝本前를 경유하는 편을 고르세요. 이 정류장까지의 버스 시간은 확인한 대표 편 기준입니다.',
    ja: '第一滝本前を経由する便をご利用ください。乗車時間は確認した代表便の目安です。',
    en: 'Choose a departure that calls at Daiichi Takimoto-mae. The ride time is based on a verified example service.',
    'zh-Hans': '请选择经停第一泷本前的班次。车程为已核查的代表班次所需时间。',
  },
  'beppu-takegawara-bus16': {
    ko: '계획 운행 자료 기준입니다. 출발 전 운영사에서 이용일의 운행을 확인하세요.', ja: '計画ダイヤに基づきます。ご利用日の運行は事業者にご確認ください。',
    en: 'Based on the scheduled feed. Check the operator’s service for your travel date.', 'zh-Hans': '基于计划时刻数据，请向运营方确认出行当日的班次。',
  },
};

export function routeLabel(key: string, locale: Locale) { return routeLabels[key]?.[locale] ?? key; }
export function routeNote(key: string, locale: Locale) { return routeNotes[key]?.[locale]; }

export function localDate(value: string, locale: Locale) {
  return new Intl.DateTimeFormat(locale, { dateStyle: 'medium', timeZone: 'Asia/Tokyo' }).format(new Date(value));
}

export function yen(value: number, locale: Locale) {
  return new Intl.NumberFormat(locale, { style: 'currency', currency: 'JPY' }).format(value);
}
