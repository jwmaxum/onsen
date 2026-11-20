"""Normalize one synthetic SimpleHotelSearch v2 page for contract review."""

import argparse
import json
import math
import sys
from pathlib import Path


FIXTURE_KIND = "onsen.synthetic.rakuten-simple-hotel-search.v1"
MAX_FIXTURE_BYTES = 1024 * 1024


class FixtureError(ValueError):
    """An unsupported or inconsistent test payload."""


def object_value(value):
    if not isinstance(value, dict):
        raise FixtureError("Expected a JSON object")
    return value


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise FixtureError("Duplicate JSON key")
        result[key] = value
    return result


def invalid_constant(_):
    raise FixtureError("Non-finite JSON value")


def integer(value, minimum, maximum):
    if type(value) is int and minimum <= value <= maximum:
        return value
    return None


def required_integer(data, key, minimum, maximum):
    value = integer(data.get(key), minimum, maximum)
    if value is None:
        raise FixtureError(f"Invalid or missing {key}")
    return value


def optional_text(value):
    if value is None:
        return ""
    if not isinstance(value, str) or len(value) > 512:
        raise FixtureError("Invalid name or address field")
    return value.strip()


def degree(value, lower, upper):
    if type(value) not in (int, float, str):
        return None
    try:
        number = float(value)
    except (ValueError, OverflowError):
        return None
    return number if math.isfinite(number) and lower <= number <= upper else None


def preview_candidate(hotel):
    if not isinstance(hotel, list) or not hotel:
        raise FixtureError("Expected the fixture's list of hotel sections")
    sections = {}
    for section in hotel:
        for key, value in object_value(section).items():
            if key in ("hotelBasicInfo", "hotelFacilitiesInfo"):
                if key in sections:
                    raise FixtureError("Duplicate hotel section")
                sections[key] = object_value(value)

    basic = sections.get("hotelBasicInfo", {})
    facilities = sections.get("hotelFacilitiesInfo", {})
    hotel_no = required_integer(basic, "hotelNo", 1, 2**63 - 1)
    name = optional_text(basic.get("hotelName"))
    if not name:
        raise FixtureError("Missing hotelName")
    address = optional_text(basic.get("address1")) + optional_text(basic.get("address2"))

    # A coarse plausibility bound for the intended Japanese survey, not a
    # check of administrative boundaries or facility-level accuracy.
    lat = degree(basic.get("latitude"), 20, 46)
    lon = degree(basic.get("longitude"), 122, 154)
    position = {"latitude": lat, "longitude": lon, "accuracy": "unverified"} if (
        lat is not None and lon is not None
    ) else None
    rooms = integer(facilities.get("hotelRoomNum"), 1, 2**31 - 1)
    minimum = integer(basic.get("hotelMinCharge"), 1, 2**31 - 1)
    return {
        "external_id": str(hotel_no),
        "name_ja": name,
        "address_ja": address or None,
        "position_hint": position,
        "room_count_hint": rooms,
        "stay_price_hint": None if minimum is None else {
            "minimum_jpy": minimum, "unit": "room_night", "indicative": True,
        },
        "on_site_onsen": None,
        "operating_status": "unknown",
        "disposition": "review_only",
    }


def preview(payload):
    envelope = object_value(payload)
    if (
        envelope.get("fixture_kind") != FIXTURE_KIND
        or type(envelope.get("formatVersion")) is not int or envelope["formatVersion"] != 2
        or type(envelope.get("datumType")) is not int or envelope["datumType"] != 1
    ):
        raise FixtureError("Expected an explicitly synthetic v2 fixture with datumType=1")
    response = object_value(envelope.get("response"))
    if "error" in response or "error_description" in response:
        raise FixtureError("API error payload is not an empty result")
    hotels = response.get("hotels")
    if not isinstance(hotels, list) or len(hotels) > 30:
        raise FixtureError("Invalid hotels list")
    paging = object_value(response.get("pagingInfo"))
    records = required_integer(paging, "recordCount", 0, 2**31 - 1)
    pages = required_integer(paging, "pageCount", 0, 100)
    page = required_integer(paging, "page", 1, 100)
    first = required_integer(paging, "first", 0, records)
    last = required_integer(paging, "last", 0, records)
    if records == 0 and (pages, page, first, last, len(hotels)) == (0, 1, 0, 0, 0):
        status = "synthetic_empty"
    else:
        if (
            not hotels or page > pages or not 1 <= first <= last
            or last - first + 1 != len(hotels) or (page == 1 and first != 1)
            or (page < pages and last == records)
        ):
            raise FixtureError("Inconsistent paging; do not mark region complete")
        status = (
            "possible_truncation" if page == pages and (pages == 100 or last < records)
            else "last_page_seen" if page == pages else "more_pages"
        )
    candidates = [preview_candidate(hotel) for hotel in hotels]
    if len({item["external_id"] for item in candidates}) != len(candidates):
        raise FixtureError("Duplicate hotel ID on one page")
    return {
        "mode": "synthetic_preview",
        "page": page,
        "page_count": pages,
        "reported_result_count": records,
        "page_status": status,
        "candidates": candidates,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("fixture", type=Path, help="A synthetic JSON fixture; no live response or DB writes")
    args = parser.parse_args(argv)
    try:
        with args.fixture.open("rb") as handle:
            body = handle.read(MAX_FIXTURE_BYTES + 1)
        if len(body) > MAX_FIXTURE_BYTES:
            raise FixtureError("Fixture exceeds 1 MiB")
        data = json.loads(body.decode("utf-8"), object_pairs_hook=unique_object, parse_constant=invalid_constant)
        result = preview(data)
    except FixtureError as error:
        parser.exit(2, f"Fixture rejected: {error}\n")
    except (OSError, UnicodeError, ValueError, RecursionError):
        parser.exit(2, "Fixture could not be read as supported UTF-8 JSON\n")
    sys.stdout.write(json.dumps(result, ensure_ascii=True, indent=2, allow_nan=False) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
