#!/usr/bin/env python3
"""
inject_data.py — gsc_data.json 을 index.html 의 DATA 객체에 주입
Usage: python3 inject_data.py --data data/gsc_data.json --html index.html
"""
import argparse
import json
import re
import sys
from pathlib import Path


# 기존 index.html 에 보존되어야 하는 DATA 키 (색인/기회/저CTR 없을 경우 fallback)
FALLBACK_INDEX = {
    "indexed": 1434,
    "not_indexed": 6271,
    "issues": [
        {"사유": "사용자가 선택한 표준이 없는 중복 페이지", "소스": "웹사이트", "페이지": 5722},
        {"사유": "리디렉션이 포함된 페이지", "소스": "웹사이트", "페이지": 29},
        {"사유": "다른 4xx 문제로 인해 차단됨", "소스": "웹사이트", "페이지": 25},
        {"사유": "찾을 수 없음(404)", "소스": "웹사이트", "페이지": 21},
        {"사유": "크롤링됨 - 현재 색인이 생성되지 않음", "소스": "Google 시스템", "페이지": 407},
        {"사유": "발견됨 - 현재 색인이 생성되지 않음", "소스": "Google 시스템", "페이지": 67},
    ],
}


def build_data_object(gsc: dict) -> str:
    """gsc_data.json → JS DATA 객체 문자열 생성"""
    chart = gsc.get("chart", [])
    keywords = gsc.get("keywords", [])
    pages = gsc.get("pages", [])
    devices = gsc.get("devices", [])
    countries = gsc.get("countries", [])
    index = gsc.get("index") or FALLBACK_INDEX
    opportunity = gsc.get("opportunity", [])
    low_ctr = gsc.get("low_ctr", [])

    def js(obj):
        return json.dumps(obj, ensure_ascii=False)

    lines = [
        "const DATA = {",
        f"  chart: {js(chart)},",
        f"  keywords: {js(keywords)},",
        f"  pages: {js(pages)},",
        f"  devices: {js(devices)},",
        f"  countries: {js(countries)},",
        f"  index: {js(index)},",
        f"  opportunity: {js(opportunity)},",
        f"  low_ctr: {js(low_ctr)}",
        "};",
    ]
    return "\n".join(lines)


def inject_into_html(html_content: str, data_js: str) -> str:
    """index.html 에서 const DATA = {...}; 블록을 교체"""
    # DATA 객체 패턴: const DATA = { ... }; (중첩 브레이스 포함)
    pattern = re.compile(
        r"(const DATA\s*=\s*)\{.*?\};",
        re.DOTALL
    )

    if not pattern.search(html_content):
        print("✗ index.html 에서 'const DATA = {...};' 블록을 찾을 수 없습니다.")
        sys.exit(1)

    # DATA 블록만 교체 (MONTH_CONFIG 등은 유지)
    new_content = pattern.sub(data_js, html_content, count=1)
    return new_content


def update_meta_comment(html_content: str, date_str: str) -> str:
    """대시보드 날짜 범위 주석 업데이트"""
    pattern = re.compile(r"(Google Search Console\s*·\s*)[\d\.\s–\-]+")
    return pattern.sub(rf"\g<1>{date_str}", html_content)


def main():
    parser = argparse.ArgumentParser(description="JSON → index.html DATA 주입기")
    parser.add_argument("--data", default="data/gsc_data.json", help="입력 JSON 경로")
    parser.add_argument("--html", default="index.html", help="대상 HTML 파일")
    parser.add_argument("--backup", action="store_true", help="HTML 백업 생성")
    args = parser.parse_args()

    print("\n[inject_data] 대시보드 업데이트 시작")

    data_path = Path(args.data)
    html_path = Path(args.html)

    if not data_path.exists():
        print(f"✗ JSON 없음: {data_path}  →  먼저 make parse 실행")
        sys.exit(1)

    if not html_path.exists():
        print(f"✗ HTML 없음: {html_path}")
        sys.exit(1)

    # 데이터 로드
    with open(data_path, encoding="utf-8") as f:
        gsc = json.load(f)

    # 날짜 범위 계산
    chart = gsc.get("chart", [])
    date_range = ""
    if chart:
        start = chart[0]["날짜"].replace("-", ".")
        end = chart[-1]["날짜"].replace("-", ".")
        date_range = f"{start} – {end}"
        print(f"  기간: {date_range}  ({len(chart)}일)")

    # HTML 백업
    if args.backup:
        backup_path = html_path.with_suffix(".html.bak")
        backup_path.write_text(html_path.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"  백업: {backup_path}")

    # HTML 읽기 + 주입
    html = html_path.read_text(encoding="utf-8")
    data_js = build_data_object(gsc)
    html = inject_into_html(html, data_js)

    # 날짜 범위 업데이트
    if date_range:
        html = update_meta_comment(html, date_range)

    # 저장
    html_path.write_text(html, encoding="utf-8")

    total_clicks = sum(d.get("클릭수", 0) for d in chart)
    total_imp = sum(d.get("노출", 0) for d in chart)
    avg_ctr = total_clicks / total_imp if total_imp else 0

    print(f"✓ {html_path} 업데이트 완료")
    print(f"  클릭수: {total_clicks:,}  |  노출수: {total_imp:,}  |  평균CTR: {avg_ctr:.2%}")


if __name__ == "__main__":
    main()
