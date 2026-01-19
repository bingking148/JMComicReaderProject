# -*- coding: utf-8 -*-
"""
JMComicReader EXE 打包脚本
一键将项目打包为独立可执行文件
"""

import os
import sys
import subprocess
import shutil

# 配置
SPEC_FILE = "build.spec"
BUILD_DIR = "build"
DIST_DIR = "dist"


def check_nuitka():
    """检查并安装Nuitka"""
    try:
        result = subprocess.run(
            ["python", "-m", "pip", "show", "nuitka"], capture_output=True, text=True
        )
        print(f"✅ Nuitka 已安装: {result.stdout.split()[0]}")
        return True
    except Exception as e:
        print(f"⚠️  Nuitka 未安装，正在自动安装...")
        try:
            subprocess.run(
                [sys.executable, "-m", "pip", "install", "nuitka", "zstandard"],
                check=True,
            )
            print("✅ Nuitka 安装成功！")
            return True
        except Exception as install_error:
            print(f"❌ Nuitka 安装失败: {install_error}")
            return False


def clean_build():
    """清理之前的构建文件"""
    if os.path.exists(BUILD_DIR):
        shutil.rmtree(BUILD_DIR)
        print("✅ 已清理旧的构建文件")


def clean_dist():
    """清理之前的分发文件"""
    if os.path.exists(DIST_DIR):
        shutil.rmtree(DIST_DIR)
        print("✅ 已清理旧的分发文件")


def build_exe():
    """打包为EXE"""
    print("=" * 60)
    print("JMComicReader EXE 打包工具")
    print("=" * 60)
    print()

    # 检查 Nuitka
    if not check_nuitka():
        print()
        print("请手动安装 Nuitka 后再试！")
        print("安装命令：pip install nuitka zstandard")
        return

    # 清理旧文件
    clean_build()
    clean_dist()

    # 确保必要目录存在
    os.makedirs("build", exist_ok=True)
    os.makedirs("dist", exist_ok=True)

    print(f"📦 开始打包 {SPEC_FILE}...")
    print()

    # 执行 Nuitka 打包
    try:
        cmd = [
            sys.executable,
            "-m",
            "nuitka",
            "--standalone",
            "--onefile",
            "--windows-console-mode=disable",
            "--assume-yes-for-downloads",
            "--plugin-enable=numpy",
            "--enable-plugin=pyside6",
            f"--output-dir={BUILD_DIR}",
            f"--output-filename={DIST_DIR}/{os.path.splitext(SPEC_FILE)[0]}_{os.sys.version}.exe",
            "--include-data-files=frontend",
            "--include-data-files=backend",
            "--file-reference=build.spec",
        ]

        subprocess.run(cmd, check=True)

        print()
        print("=" * 60)
        print("✅ 打包成功！")
        print("=" * 60)
        print()

        # 查找生成的EXE文件
        exe_name = f"{os.path.splitext(SPEC_FILE)[0]}_{os.sys.version}.exe"
        exe_path = os.path.join(DIST_DIR, exe_name)

        if os.path.exists(exe_path):
            file_size = os.path.getsize(exe_path)
            file_size_mb = file_size / (1024 * 1024)

            print(f"📦 EXE 文件位置: {exe_path}")
            print(f"📏 文件大小: {file_size_mb:.2f} MB")
            print()
            print("🎯 使用说明:")
            print()
            print("1. 复制整个项目文件夹到目标电脑")
            print("2. 双击运行 JMComicReader.exe")
            print("3. 首次运行会自动创建数据库和配置文件")
            print("4. 访问 http://localhost:5000 开始使用")
            print()
            print("📁 打包目录:")
            print(f"   {DIST_DIR}/")
            print()
            print("🔧 配置文件:")
            print(f"   {SPEC_FILE}")
            print()
        else:
            print("❌ 打包失败，未找到生成的EXE文件")

    except Exception as e:
        print()
        print("=" * 60)
        print(f"❌ 打包失败: {e}")
        print("=" * 60)


if __name__ == "__main__":
    build_exe()
