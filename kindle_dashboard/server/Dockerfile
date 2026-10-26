FROM python:3.12-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TZ=Asia/Tokyo

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 日本語フォント（Noto Sans JP 可変ウェイト版, SIL OFL）
RUN mkdir fonts && python -c "import urllib.request; urllib.request.urlretrieve('https://raw.githubusercontent.com/google/fonts/main/ofl/notosansjp/NotoSansJP%5Bwght%5D.ttf', 'fonts/NotoSansJP-VF.ttf')"

COPY dashboard/ dashboard/
COPY serve.py .

RUN useradd --system --no-create-home app
USER app

EXPOSE 8080
HEALTHCHECK --interval=60s --timeout=10s --start-period=20s \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=5)"

# 設定は /config/config.json（無ければ既定値: 東京）
CMD ["python", "serve.py", "--config", "/config/config.json"]
