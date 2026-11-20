"""Stage, review, and publish the four-language Takegawara pilot on a loopback DB."""

import argparse
import sys
from dataclasses import dataclass
from uuid import NAMESPACE_URL, uuid5

from ingest.takegawara import (
    ANALYZED_ON,
    MIXED_QUALITY,
    SAMPLED_ON,
    SAMPLES,
    ImportBlocked,
    connect_local_db,
)

REVIEWER = "phase3_ai_source_review"


@dataclass(frozen=True)
class Language:
    facility_name: str
    sample_names: tuple[str, str, str]
    mixed_quality: str
    bicarbonate_quality: str
    sample_note: str
    attribution: str
    transformation: str


LANGUAGES = {
    "ja": Language(
        "竹瓦温泉", ("男湯", "女湯", "砂湯"), MIXED_QUALITY, "ナトリウム－炭酸水素塩温泉",
        "2019年に源泉の貯湯設備から採取した試料の分析結果です。温度は採水時の測定値です。",
        "出典は別府市が公開した温泉分析書です。原本と利用日を併記しています。",
        "分析書の測定値と泉質を転記し、表示用に整理しました。",
    ),
    "ko": Language(
        "다케가와라 온천", ("남탕", "여탕", "모래탕"),
        "나트륨·칼슘·마그네슘 염화물·탄산수소염천", "나트륨 탄산수소염천",
        "2019년 원천 저장 시설에서 채취한 시료의 분석 결과입니다. 온도는 채수 당시 측정값입니다.",
        "출처는 벳푸시가 공개한 온천 분석서입니다. 원본 링크와 이용일을 함께 표시합니다.",
        "분석서의 측정값과 천질을 전사하고, 표시를 위해 정리·번역했습니다.",
    ),
    "en": Language(
        "Takegawara Onsen", ("Men’s bath", "Women’s bath", "Sand bath"),
        "Sodium–calcium–magnesium chloride–bicarbonate spring", "Sodium bicarbonate spring",
        "This analysis covers a 2019 sample from the spring-water storage system. The temperature was measured at sampling.",
        "Source is the hot spring analysis report published by Beppu City. The original report and access date are provided.",
        "Measurements and spring classification were transcribed, organized and translated for display.",
    ),
    "zh-Hans": Language(
        "竹瓦温泉", ("男浴池", "女浴池", "沙浴"),
        "钠—钙—镁氯化物／碳酸氢盐温泉", "钠碳酸氢盐温泉",
        "本记录为2019年从源泉储水设施取样所得的分析结果。所示温度为采样时的实测值。",
        "来源为别府市公开的温泉分析报告，并附原始报告链接及访问日期。",
        "已转录报告中的测量数据和泉质分类，并进行整理和翻译。",
    ),
}


def analysis_id(sample):
    return uuid5(NAMESPACE_URL, sample.url + "#" + sample.sha256)


def localized_text(sample_index, language):
    sample = SAMPLES[sample_index]
    quality = language.mixed_quality if "chloride" in sample.quality_codes else language.bicarbonate_quality
    return (language.facility_name, language.sample_names[sample_index], quality,
            language.sample_note, language.attribution, language.transformation)


def verified_revision(connection, sample):
    row = connection.execute("""
        select source_revision, facility_slug, bath_name_ja, source_url, content_sha256, sampled_on, analyzed_on,
            source_temp_celsius, ph_onsite, ph_laboratory, quality_label_ja, quality_codes
        from core.analysis_source_facts where analysis_id = %s
    """, (analysis_id(sample),)).fetchone()
    expected = ("takegawara-onsen", sample.bath_name, sample.url, sample.sha256, SAMPLED_ON, ANALYZED_ON,
                sample.temperature, sample.ph_onsite, sample.ph_laboratory, sample.quality, sorted(sample.quality_codes))
    if row is None or row[1:] != expected:
        raise ImportBlocked(f"Stored facts or source rights need review for {sample.key}")
    return row[0]


def stage_translations(connection, identifier, revision, texts):
    count = 0
    for locale, text in texts.items():
        count += connection.execute("""
            insert into core.analysis_translations (analysis_id, locale, source_revision, facility_name, sample_name,
                quality_name, sample_note, source_attribution, source_transformation)
            values (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            on conflict (analysis_id, locale) do update set source_revision = excluded.source_revision,
                facility_name = excluded.facility_name, sample_name = excluded.sample_name,
                quality_name = excluded.quality_name, sample_note = excluded.sample_note,
                source_attribution = excluded.source_attribution, source_transformation = excluded.source_transformation
            where analysis_translations.source_revision is distinct from excluded.source_revision
        """, (identifier, locale, revision, *text)).rowcount
    return count


def review_translations(connection, identifier, revision, texts):
    rows = connection.execute("""
        select locale, facility_name, sample_name, quality_name, sample_note, source_attribution, source_transformation
        from core.analysis_translations where analysis_id = %s and source_revision = %s for update
    """, (identifier, revision)).fetchall()
    if {row[0]: row[1:] for row in rows} != texts:
        raise ImportBlocked("All four drafts must match the reviewed localized text and current source revision")

    connection.execute("""
        insert into core.analysis_fact_reviews (analysis_id, source_revision, review_state, reviewed_by, reviewed_at)
        values (%s, %s, 'approved', %s, statement_timestamp())
        on conflict (analysis_id) do update set source_revision = excluded.source_revision,
            review_state = excluded.review_state, reviewed_by = excluded.reviewed_by, reviewed_at = excluded.reviewed_at
        where analysis_fact_reviews.source_revision is distinct from excluded.source_revision
           or analysis_fact_reviews.review_state <> 'approved'
    """, (identifier, revision, REVIEWER))
    return connection.execute("""
        update core.analysis_translations set review_state = 'approved', reviewed_by = %s, reviewed_at = statement_timestamp()
        where analysis_id = %s and source_revision = %s and review_state <> 'approved'
    """, (REVIEWER, identifier, revision)).rowcount


def apply_command(connection, command):
    with connection.transaction():
        if command in {"publish", "withdraw"}:
            connection.execute("set local role onsen_publisher")
            operation = ("select core.publish_spring_analysis(%s)" if command == "publish"
                         else "select core.withdraw_spring_analysis(%s)")
            return sum(connection.execute(operation, (analysis_id(sample),)).fetchone()[0] for sample in SAMPLES)

        connection.execute("set local role onsen_reviewer")
        operation = stage_translations if command == "stage" else review_translations
        changed = 0
        for index, sample in enumerate(SAMPLES):
            revision = verified_revision(connection, sample)
            texts = {locale: localized_text(index, language) for locale, language in LANGUAGES.items()}
            changed += operation(connection, analysis_id(sample), revision, texts)
        return changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("stage", "review", "publish", "withdraw"))
    args = parser.parse_args()
    try:
        import psycopg
    except ImportError:
        print("Install ingest/requirements.txt before applying", file=sys.stderr)
        return 1
    try:
        with connect_local_db() as connection:
            changed = apply_command(connection, args.command)
    except ImportBlocked as error:
        print(f"Publication blocked: {error}", file=sys.stderr)
        return 1
    except psycopg.Error as error:
        if args.command == "publish" and error.sqlstate == "23514":
            print("Publication blocked: approve current facts and all four translations first", file=sys.stderr)
        else:
            print(f"Publication failed at the database (SQLSTATE {error.sqlstate or 'unavailable'})", file=sys.stderr)
        return 1
    print(f"{args.command}: {changed} changes")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
