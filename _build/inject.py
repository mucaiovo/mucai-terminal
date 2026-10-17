#!/usr/bin/env python3
"""把真实配置文件注入模板，生成最终可分发的 Install-MucaiTerminal.ps1。

为什么要这么做：starship.toml 里有大量 Nerd Font 私有区图标（powerline 分隔符等），
手工抄写极易出错。这里直接读真实文件，保证注入的内容逐字节一致。

用法：
    python inject.py
"""
import os
import sys

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

BUILD_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_DIR = os.path.dirname(BUILD_DIR)
WORKSPACE = os.path.dirname(PROJECT_DIR)

TEMPLATE = os.path.join(BUILD_DIR, "Install-MucaiTerminal.template.ps1")
OUTPUT = os.path.join(PROJECT_DIR, "Install-MucaiTerminal.ps1")

STARSHIP = os.path.join(BUILD_DIR, "reference", "expected", "starship.toml")
# fastfetch 配置不能直接沿用 Linux 端那份：Windows 的默认 logo 会用到 9 个颜色槽位中的多个，
# 而 Linux 那份只填了 1、2，剩下的会回退到 fastfetch 内置配色 —— logo 变成双拼色。
# 所以这里用 Windows 版（9 个槽位都填满），它由 _build/reference/templates/
# fastfetch-config.jsonc 经 matugen 渲染得到。
FASTFETCH = os.path.join(PROJECT_DIR, "_build", "matugen", "fastfetch-installed.jsonc")

# matugen 那一套（给新机器铺模板/配置/命令/回滚脚本）
MUCAI_REGEN = os.path.join(PROJECT_DIR, "mucai-regen.ps1")
UNINSTALL = os.path.join(PROJECT_DIR, "Uninstall-MucaiTerminal.ps1")
UPDATE_MATUGEN = os.path.join(PROJECT_DIR, "Update-Matugen.ps1")
MATUGEN_CONFIG = os.path.join(BUILD_DIR, "matugen", "config.toml")
MATUGEN_TPL_STARSHIP = os.path.join(BUILD_DIR, "reference", "templates", "starship-colors.toml")
MATUGEN_TPL_FASTFETCH = os.path.join(BUILD_DIR, "reference", "templates", "fastfetch-config.jsonc")
MATUGEN_TPL_WTCOLORS = os.path.join(BUILD_DIR, "matugen", "templates", "windows-terminal-colors.txt")
MATUGEN_TPL_WTANSI = os.path.join(BUILD_DIR, "matugen", "templates", "windows-terminal-ansi.txt")
MATUGEN_TPL_OPENCODE = os.path.join(BUILD_DIR, "matugen", "templates", "opencode-theme.json")
# 内置的 matugen.exe（gzip + base64）。取 _build/matugen 下最新的 matugen-*.gzb64；
# 一个都没有时，生成"不带内置 exe"的脚本。
def _find_matugen_blob():
    import glob
    d = os.path.join(BUILD_DIR, "matugen")
    cands = sorted(glob.glob(os.path.join(d, "matugen-*.gzb64")), key=os.path.getmtime, reverse=True)
    return cands[0] if cands else os.path.join(d, "matugen-none.gzb64")


MATUGEN_BLOB = _find_matugen_blob()
MATUGEN_TPL_SOURCECOLOR = os.path.join(BUILD_DIR, "matugen", "templates", "source-color.txt")
LIVE_PROFILE = os.path.join(
    os.environ.get("USERPROFILE", os.path.expanduser("~")),
    "Documents", "PowerShell", "Microsoft.PowerShell_profile.ps1",
)


def read_text(path):
    with open(path, "r", encoding="utf-8-sig") as fh:
        return fh.read()


def to_lf(text):
    return text.replace("\r\n", "\n").replace("\r", "\n")


def guard_here_string(name, text):
    """单引号 here-string 里，任何以 '@ 开头的行都会提前终止字符串。"""
    for lineno, line in enumerate(text.split("\n"), 1):
        if line.startswith("'@"):
            raise SystemExit(
                "%s 第 %d 行以 '@ 开头，会截断 here-string，需要改写该行" % (name, lineno)
            )


def split_profile(text):
    """把 profile 拆成「主体」和「启动画面」两段，后者可以用 -NoBanner 省掉。"""
    lines = text.splitlines(keepends=True)
    marker = None
    for i, line in enumerate(lines):
        if "6. 启动装潢" in line:
            marker = i
            break
    if marker is None:
        raise SystemExit("profile 里找不到 '# 6. 启动装潢' 标记，无法拆分启动画面")

    j = marker - 1
    while j >= 0 and lines[j].strip().startswith("# ---"):
        j -= 1
    split = j + 1
    return "".join(lines[:split]), "".join(lines[split:])


def main():
    template = read_text(TEMPLATE)

    starship = to_lf(read_text(STARSHIP))
    fastfetch = to_lf(read_text(FASTFETCH))

    profile = to_lf(read_text(LIVE_PROFILE))
    profile_head, profile_banner = split_profile(profile)

    # 内置 matugen.exe（可选）
    matugen_blob = ""
    if os.path.exists(MATUGEN_BLOB):
        matugen_blob = to_lf(read_text(MATUGEN_BLOB)).strip()
    else:
        print("  提示: 没找到 %s，将生成不含内置 matugen.exe 的脚本" % os.path.basename(MATUGEN_BLOB))

    payloads = {
        "#__PAYLOAD_MATUGEN_BLOB__": ("内置 matugen.exe (gzip+base64)", matugen_blob),
        "#__PAYLOAD_STARSHIP_TOML__": ("starship.toml", starship),
        "#__PAYLOAD_FASTFETCH_CONFIG__": ("fastfetch config.jsonc", fastfetch),
        "#__PAYLOAD_PROFILE_HEAD__": ("profile 主体", profile_head),
        "#__PAYLOAD_PROFILE_BANNER__": ("profile 启动画面段", profile_banner),
        "#__PAYLOAD_MUCAI_REGEN__": ("mucai-regen.ps1", to_lf(read_text(MUCAI_REGEN))),
        "#__PAYLOAD_UNINSTALL__": ("Uninstall-MucaiTerminal.ps1", to_lf(read_text(UNINSTALL))),
        "#__PAYLOAD_UPDATE_MATUGEN__": ("Update-Matugen.ps1", to_lf(read_text(UPDATE_MATUGEN))),
        "#__PAYLOAD_MATUGEN_CONFIG__": ("matugen config.toml", to_lf(read_text(MATUGEN_CONFIG))),
        "#__PAYLOAD_TPL_STARSHIP__": ("模板 starship-colors.toml", to_lf(read_text(MATUGEN_TPL_STARSHIP))),
        "#__PAYLOAD_TPL_FASTFETCH__": ("模板 fastfetch-config.jsonc", to_lf(read_text(MATUGEN_TPL_FASTFETCH))),
        "#__PAYLOAD_TPL_WTCOLORS__": ("模板 windows-terminal-colors.txt", to_lf(read_text(MATUGEN_TPL_WTCOLORS))),
        "#__PAYLOAD_TPL_WTANSI__": ("模板 windows-terminal-ansi.txt", to_lf(read_text(MATUGEN_TPL_WTANSI))),
        "#__PAYLOAD_TPL_SOURCECOLOR__": ("模板 source-color.txt", to_lf(read_text(MATUGEN_TPL_SOURCECOLOR))),
        "#__PAYLOAD_TPL_OPENCODE__": ("模板 opencode-theme.json", to_lf(read_text(MATUGEN_TPL_OPENCODE))),
    }

    out = template
    for marker, (name, body) in payloads.items():
        if marker not in out:
            raise SystemExit("模板里找不到标记 %s" % marker)
        guard_here_string(name, body)
        out = out.replace(marker, body)

    if "__PAYLOAD_" in out:
        raise SystemExit("还有未替换的标记，模板和注入表不一致")

    out = to_lf(out).replace("\n", "\r\n")  # Windows 原生换行
    with open(OUTPUT, "w", encoding="utf-8-sig", newline="") as fh:
        fh.write(out)

    print("生成: %s" % OUTPUT)
    print("  模板     %6d 行" % (template.count("\n") + 1))
    print("  最终     %6d 行" % (out.count("\r\n") + 1))
    for name, body in payloads.values():
        print("  注入 %-34s %6d 行" % (name, body.count("\n") + 1))

    # --- 自检：每个载荷必须原样落在生成的脚本里（逐字节，忽略换行差异）---
    flat = to_lf(out)
    bad = [name for name, body in payloads.values() if to_lf(body) not in flat]
    if bad:
        raise SystemExit("自检失败：这些载荷没有原样落到脚本里 -> %s" % ", ".join(bad))
    print("  自检     全部 %d 个载荷均已逐字节落入" % len(payloads))
    return 0


if __name__ == "__main__":
    sys.exit(main())
