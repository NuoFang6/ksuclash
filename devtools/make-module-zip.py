#!/usr/bin/env python3
"""make-module-zip.py - 打包模块 zip：正斜杠路径 + 保留可执行位 + 排除源码目录
用法: python3 devtools/make-module-zip.py [module-root] [output.zip]
默认: 从 module/ 打包到 suclash-module.zip
"""
import os
import stat
import sys
import zipfile

src = sys.argv[1] if len(sys.argv) > 1 else "module"
out = sys.argv[2] if len(sys.argv) > 2 else "suclash-module.zip"
EXCLUDE_DIRS = {"webroot-src"}          # 面板/页面源码不进 zip（webroot 才是产物）
EXEC_FILES = {"mihomo", "suclash_helper", "clashctl", "service.sh", "customize.sh", "uninstall.sh", "action.sh"}
EXEC_EXT = {".sh"}

if not os.path.isfile(os.path.join(src, "module.prop")):
    sys.exit("module.prop not found under " + src)

def zi_mode(path, name):
    # 模块按架构单独打包，bin/ 下是单一架构的无后缀二进制，均需可执行位
    if name in EXEC_FILES or os.path.splitext(name)[1] in EXEC_EXT:
        return (stat.S_IFREG | 0o755) << 16
    return (stat.S_IFREG | 0o644) << 16

n = 0
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for root, dirs, files in os.walk(src):
        dirs[:] = [d for d in sorted(dirs) if d not in EXCLUDE_DIRS]
        for f in sorted(files):
            full = os.path.join(root, f)
            arc = os.path.relpath(full, src).replace(os.sep, "/")
            info = zipfile.ZipInfo(arc)
            info.external_attr = zi_mode(full, f)
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(full, "rb") as fh:
                z.writestr(info, fh.read())
            n += 1
print(f"{out}: {n} files")
