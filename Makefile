# ─────────────────────────────────────────────────
# 센트온 SEO 대시보드 자동화 Makefile
# ─────────────────────────────────────────────────
WEBHOOK_URL := https://hook.us2.make.com/kl5b5hphmqdql08ysvdmk7fa29lo2u0p
PORT        := 8080
DATA_DIR    := data
SCRIPTS_DIR := scripts
XLSX_PERF   := $(wildcard scenton_search-console_실적*.xlsx)
XLSX_INDEX  := $(wildcard scenton_searchconsole_색인*.xlsx)
OUTPUT_HTML := index.html
DATA_JSON   := $(DATA_DIR)/gsc_data.json

.PHONY: help serve open trigger parse build clean watch check-deps install-deps

# ─── 기본: 도움말 ───────────────────────────────
help:
	@printf "\n\033[1;34m센트온 SEO 대시보드 자동화\033[0m\n"
	@printf "\033[90m──────────────────────────────────────\033[0m\n"
	@printf "  \033[32mmake serve\033[0m        로컬 서버 시작 (http://localhost:$(PORT))\n"
	@printf "  \033[32mmake open\033[0m         브라우저에서 대시보드 열기\n"
	@printf "  \033[32mmake parse\033[0m        xlsx → JSON 변환\n"
	@printf "  \033[32mmake build\033[0m        xlsx 파싱 후 대시보드 재생성\n"
	@printf "  \033[32mmake trigger\033[0m      Make.com 시나리오 수동 실행\n"
	@printf "  \033[32mmake watch\033[0m        xlsx 변경 감지 후 자동 빌드\n"
	@printf "  \033[32mmake clean\033[0m        임시 파일 정리\n"
	@printf "  \033[32mmake install-deps\033[0m 필수 Python 패키지 설치\n"
	@printf "\033[90m──────────────────────────────────────\033[0m\n\n"

# ─── 의존성 체크 ────────────────────────────────
check-deps:
	@python3 -c "import openpyxl" 2>/dev/null || (printf "\033[31m✗ openpyxl 미설치. make install-deps 실행\033[0m\n" && exit 1)
	@printf "\033[32m✓ 의존성 확인 완료\033[0m\n"

install-deps:
	@printf "\033[34m→ 필수 패키지 설치 중...\033[0m\n"
	pip3 install openpyxl --quiet
	@printf "\033[32m✓ 설치 완료\033[0m\n"

# ─── 로컬 서버 ──────────────────────────────────
serve:
	@printf "\033[34m→ 로컬 서버 시작: \033[4mhttp://localhost:$(PORT)\033[0m\n"
	@printf "\033[90m  Ctrl+C 로 종료\033[0m\n\n"
	python3 -m http.server $(PORT)

open:
	@open http://localhost:$(PORT) 2>/dev/null || xdg-open http://localhost:$(PORT)

# ─── 데이터 파싱 ────────────────────────────────
$(DATA_DIR):
	mkdir -p $(DATA_DIR)

parse: check-deps $(DATA_DIR)
	@if [ -z "$(XLSX_PERF)" ]; then \
		printf "\033[31m✗ 실적 xlsx 파일을 찾을 수 없습니다\033[0m\n"; exit 1; \
	fi
	@printf "\033[34m→ xlsx 파싱 중...\033[0m\n"
	@printf "  실적: $(XLSX_PERF)\n"
	@printf "  색인: $(XLSX_INDEX)\n"
	python3 $(SCRIPTS_DIR)/parse_xlsx.py \
		--perf "$(XLSX_PERF)" \
		--index "$(XLSX_INDEX)" \
		--out "$(DATA_JSON)"
	@printf "\033[32m✓ $(DATA_JSON) 생성 완료\033[0m\n"

# ─── 대시보드 빌드 ──────────────────────────────
build: parse
	@printf "\033[34m→ 대시보드 재빌드 중...\033[0m\n"
	python3 $(SCRIPTS_DIR)/inject_data.py \
		--data "$(DATA_JSON)" \
		--html "$(OUTPUT_HTML)"
	@printf "\033[32m✓ $(OUTPUT_HTML) 업데이트 완료\033[0m\n"
	@python3 -c "import json,os; d=json.load(open('$(DATA_JSON)')); \
		c=d.get('chart',[]); \
		total=sum(x.get('클릭수',0) for x in c); \
		print(f'  📊 총 클릭수: {total:,}  |  일수: {len(c)}일')"

# ─── Make.com 웹훅 트리거 ───────────────────────
trigger:
	@printf "\033[34m→ Make.com 시나리오 트리거 중...\033[0m\n"
	@RESPONSE=$$(curl -s -w "\n%{http_code}" -X POST "$(WEBHOOK_URL)" \
		-H "Content-Type: application/json" \
		-d "{\"source\":\"makefile\",\"action\":\"generate_report\",\"timestamp\":\"$$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"); \
	HTTP_CODE=$$(echo "$$RESPONSE" | tail -1); \
	BODY=$$(echo "$$RESPONSE" | head -1); \
	if [ "$$HTTP_CODE" = "200" ]; then \
		printf "\033[32m✓ 시나리오 실행 완료 (HTTP $$HTTP_CODE)\033[0m\n"; \
		printf "  응답: $$BODY\n"; \
	else \
		printf "\033[31m✗ 실패 (HTTP $$HTTP_CODE): $$BODY\033[0m\n"; exit 1; \
	fi

# ─── 파일 변경 감지 자동 빌드 ──────────────────
watch:
	@printf "\033[34m→ xlsx 변경 감지 중... (Ctrl+C 로 종료)\033[0m\n"
	@which fswatch > /dev/null 2>&1 && \
		fswatch -o --include=".*\.xlsx$$" . | xargs -n1 -I{} sh -c 'printf "\n\033[33m⟳ 변경 감지 — 재빌드\033[0m\n"; make build' || \
	(printf "\033[33m⚠ fswatch 미설치 — 폴링 모드로 전환\033[0m\n"; \
		PREV=""; while true; do \
			CURR=$$(ls -lm $(XLSX_PERF) $(XLSX_INDEX) 2>/dev/null); \
			if [ "$$CURR" != "$$PREV" ]; then \
				[ -n "$$PREV" ] && printf "\n\033[33m⟳ 변경 감지 — 재빌드\033[0m\n" && make build; \
				PREV="$$CURR"; \
			fi; \
			sleep 5; \
		done)

# ─── JSON만 주입 (parse 생략) ───────────────────
inject: $(DATA_DIR)
	@if [ ! -f "$(DATA_JSON)" ]; then \
		printf "\033[31m✗ $(DATA_JSON) 없음 — 구글시트에서 JSON을 먼저 복사하세요\033[0m\n"; exit 1; \
	fi
	@printf "\033[34m→ 대시보드 업데이트 중...\033[0m\n"
	python3 $(SCRIPTS_DIR)/inject_data.py \
		--data "$(DATA_JSON)" \
		--html "$(OUTPUT_HTML)"
	@printf "\033[32m✓ $(OUTPUT_HTML) 업데이트 완료\033[0m\n"

# ─── JSON 주입 + git push ────────────────────────
update: inject
	@printf "\033[34m→ GitHub에 푸시 중...\033[0m\n"
	git add $(OUTPUT_HTML)
	git commit -m "chore: 대시보드 업데이트 $$(date '+%Y-%m-%d')"
	git push
	@printf "\033[32m✓ GitHub Pages 반영 완료 (1~2분 소요)\033[0m\n"

# ─── 정리 ───────────────────────────────────────
clean:
	rm -rf $(DATA_DIR)
	find . -name "*.pyc" -delete
	find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null; true
	@printf "\033[32m✓ 정리 완료\033[0m\n"

.DEFAULT_GOAL := help
