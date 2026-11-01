# ビルドしたファームウェアを build/firmware.bin にコピーする（ダッシュボードの「ファームウェアを更新」で選びやすいように。
# .pio は隠しフォルダなので、Finder やファイル選択の画面では見つけにくい）
import os
import shutil

Import("env")  # noqa: F821  （PlatformIO が用意する）


def copy_bin(source, target, env):
    out = os.path.join(env.subst("$PROJECT_DIR"), "build")
    os.makedirs(out, exist_ok=True)
    shutil.copy(str(target[0]), os.path.join(out, "firmware.bin"))
    print("ファームウェアを build/firmware.bin にコピーしました")


env.AddPostAction("$BUILD_DIR/${PROGNAME}.bin", copy_bin)  # noqa: F821
