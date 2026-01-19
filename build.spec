# -*- mode: python ; coding: utf-8 -*-
"""
JMComicReader EXE 打包配置
使用 Nuitka 将 Python 项目打包为独立 EXE 文件
"""

import os

# 模块模式：standaloneexefile（推荐）
# 优点：启动速度快，exe体积小
# 缺点：无法启动时实时加载网页资源（已优化）
mode = "standaloneexefile"

# 项目基本信息
app_name = "JMComicReader"
version = "1.0.0"

# 入口文件
entry_point = "start.py"

# 图标（可选）
icon = None

# 公司信息
company_name = "JMComicReader"
product_name = "JMComicReader"
file_version = version
copyright = "2026"

# 包含的数据文件
datas = [
    # 包含整个项目目录
    ("frontend", "frontend"),
    ("backend", "backend"),
]

# 不包含的文件
excludes = [
    # 测试文件
    "**/test*.py",
    # __pycache__
    "**/__pycache__",
    "**/*.pyc",
]

# Nuitka 特定选项
options = [
    # 优化级别：-O2（推荐，平衡性能和大小）
    "-O2",

    # 禁用控制台（可选，如果不想显示黑色窗口可以启用）
    # "--windows-disable-console",

    # 启用 LTO 优化（链接时优化，减小体积）
    "--lto=yes",

    # 启用 PGO（引导优化，首次打包需要训练，后续打包快）
    "--enable-plugin=pgo",

    # 输出格式
    f"--output-dir=build/{mode}",

    # 移除断言（减小体积）
    "--remove-output",

    # 包含数据文件模式
    f"--include-data-dir=../",

    # Windows 平台特定选项
    "--mingw64",  # 64位 Windows
    "--windows-company-name="JMComicReader"",
]

# Python 版本
python_version = "3.11"

# 插件选项
# plugins = [
#     "enum-compat",  # 枚举兼容
#     "pylint-warnings",  # Pylint 警告
# ]

# 输出配置
[NUITKA]
# 模式选择
plugin-mode = mode

# 应用名称
application = app_name

# 版本信息
version = version

# 公司名称
company = company_name

# 产品名称
product = product_name

# 文件版本
file_version = file_version

# 版权信息
copyright_str = copyright

# 入口点
entry_point = entry_point

# 图标
icon = icon

# 数据文件
datas = datas

# 排除文件
excludes = excludes

# 选项
options = options

# Python 版本
python_version = python_version

# 插件
# plugins = plugins
