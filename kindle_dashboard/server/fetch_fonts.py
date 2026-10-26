#!/usr/bin/env python3
"""表示に使うフォント（Google Fonts, SIL OFL）を fonts/ にダウンロードする。

  python fetch_fonts.py
"""

import sys
import urllib.request
from pathlib import Path

BASE = "https://raw.githubusercontent.com/google/fonts/main/ofl/"

# 保存名: Google Fonts リポジトリ内のパス
FONTS = {
    "NotoSansJP-VF.ttf": "notosansjp/NotoSansJP%5Bwght%5D.ttf",  # 日本語（全体）
    # 時計の数字の候補（config.json の clock.font で選ぶ）
    "Outfit-VF.ttf": "outfit/Outfit%5Bwght%5D.ttf",
    "Montserrat-VF.ttf": "montserrat/Montserrat%5Bwght%5D.ttf",
    "JosefinSans-VF.ttf": "josefinsans/JosefinSans%5Bwght%5D.ttf",
    "BebasNeue-Regular.ttf": "bebasneue/BebasNeue-Regular.ttf",
    "Oswald-VF.ttf": "oswald/Oswald%5Bwght%5D.ttf",
    "DMSerifDisplay-Regular.ttf": "dmserifdisplay/DMSerifDisplay-Regular.ttf",
    "SpaceGrotesk-VF.ttf": "spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf",
    "Urbanist-VF.ttf": "urbanist/Urbanist%5Bwght%5D.ttf",
    "Lexend-VF.ttf": "lexend/Lexend%5Bwght%5D.ttf",
}


def main() -> int:
    out = Path(__file__).resolve().parent / "fonts"
    out.mkdir(exist_ok=True)
    for name, path in FONTS.items():
        dest = out / name
        if dest.exists():
            continue
        print(f"ダウンロード: {name}")
        urllib.request.urlretrieve(BASE + path, dest)
    print(f"{out} に保存しました")
    return 0


if __name__ == "__main__":
    sys.exit(main())
