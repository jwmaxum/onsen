create schema if not exists extensions;
create extension if not exists postgis with schema extensions;
create schema core;
create schema ingest;
create schema api;

revoke all on schema core, ingest, api from public, anon, authenticated, service_role;

create table core.prefectures (
    code char(2) primary key check (code ~ '^(0[1-9]|[1-3][0-9]|4[0-7])$'),
    name_ja text not null unique,
    name_en text not null unique
);

create table core.municipalities (
    code char(5) primary key check (code ~ '^[0-9]{5}$'),
    prefecture_code char(2) not null references core.prefectures,
    name_ja text not null,
    unique (code, prefecture_code),
    check (left(code, 2) = prefecture_code)
);

create table core.locales (
    code text primary key check (code ~ '^[a-z]{2,3}(-[A-Za-z0-9]{2,8})*$'),
    display_name text not null
);

create table core.quality_codes (
    code text primary key,
    name_ja text not null unique
);

create table core.quality_aliases (
    alias_ja text not null,
    quality_code text not null references core.quality_codes,
    primary key (alias_ja, quality_code)
);

insert into core.prefectures values
    ('01', '北海道', 'Hokkaido'), ('02', '青森県', 'Aomori'), ('03', '岩手県', 'Iwate'),
    ('04', '宮城県', 'Miyagi'), ('05', '秋田県', 'Akita'), ('06', '山形県', 'Yamagata'),
    ('07', '福島県', 'Fukushima'), ('08', '茨城県', 'Ibaraki'), ('09', '栃木県', 'Tochigi'),
    ('10', '群馬県', 'Gunma'), ('11', '埼玉県', 'Saitama'), ('12', '千葉県', 'Chiba'),
    ('13', '東京都', 'Tokyo'), ('14', '神奈川県', 'Kanagawa'), ('15', '新潟県', 'Niigata'),
    ('16', '富山県', 'Toyama'), ('17', '石川県', 'Ishikawa'), ('18', '福井県', 'Fukui'),
    ('19', '山梨県', 'Yamanashi'), ('20', '長野県', 'Nagano'), ('21', '岐阜県', 'Gifu'),
    ('22', '静岡県', 'Shizuoka'), ('23', '愛知県', 'Aichi'), ('24', '三重県', 'Mie'),
    ('25', '滋賀県', 'Shiga'), ('26', '京都府', 'Kyoto'), ('27', '大阪府', 'Osaka'),
    ('28', '兵庫県', 'Hyogo'), ('29', '奈良県', 'Nara'), ('30', '和歌山県', 'Wakayama'),
    ('31', '鳥取県', 'Tottori'), ('32', '島根県', 'Shimane'), ('33', '岡山県', 'Okayama'),
    ('34', '広島県', 'Hiroshima'), ('35', '山口県', 'Yamaguchi'), ('36', '徳島県', 'Tokushima'),
    ('37', '香川県', 'Kagawa'), ('38', '愛媛県', 'Ehime'), ('39', '高知県', 'Kochi'),
    ('40', '福岡県', 'Fukuoka'), ('41', '佐賀県', 'Saga'), ('42', '長崎県', 'Nagasaki'),
    ('43', '熊本県', 'Kumamoto'), ('44', '大分県', 'Oita'), ('45', '宮崎県', 'Miyazaki'),
    ('46', '鹿児島県', 'Kagoshima'), ('47', '沖縄県', 'Okinawa');

insert into core.municipalities (code, prefecture_code, name_ja) values
    ('01214', '01', '稚内市'), ('01230', '01', '登別市'), ('44202', '44', '別府市');

insert into core.locales values ('ja', '日本語'), ('ko', '한국어'),
    ('en', 'English'), ('zh-Hans', '简体中文');

insert into core.quality_codes values
    ('simple', '単純温泉'), ('chloride', '塩化物泉'), ('bicarbonate', '炭酸水素塩泉'),
    ('sulfate', '硫酸塩泉'), ('carbon_dioxide', '二酸化炭素泉'), ('iron', '含鉄泉'),
    ('acidic', '酸性泉'), ('iodine', '含よう素泉'), ('sulfur', '硫黄泉'), ('radioactive', '放射能泉');

insert into core.quality_aliases select name_ja, code from core.quality_codes;
insert into core.quality_aliases values ('含ヨウ素泉', 'iodine'), ('含ようそ泉', 'iodine');
