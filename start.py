#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
JMComicReader 启动脚本
禁用自动重载，避免调试模式无限重启
"""

import os
import sys

# 设置工作目录
os.chdir(os.path.dirname(os.path.abspath(__file__)))

# 导入Flask应用
from backend.app import app

if __name__ == "__main__":
    print("=" * 50)
    print("JMComicReader 启动中...")
    print("=" * 50)
    print()
    print("访问地址：")
    print("  - 本地:   http://localhost:5000")
    print("  - 局域网: http://0.0.0.0:5000")
    print()
    print("按 Ctrl+C 停止服务")
    print("=" * 50)
    print()

    # 禁用自动重载，使用生产模式设置
    app.run(
        host="0.0.0.0",
        port=5000,
        debug=False,  # 关闭调试模式
        use_reloader=False,  # 关闭自动重载
        threaded=True,  # 启用多线程
    )
