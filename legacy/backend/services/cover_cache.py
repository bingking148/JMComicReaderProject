#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
封面缓存模块
"""

import os
import json
from typing import Dict, Optional


class CoverCache:
    """封面缓存管理器"""

    def __init__(self, cache_dir: str):
        self.cache_dir = cache_dir
        self.cache_file = os.path.join(cache_dir, "cover_cache.json")
        self.cache: Dict[str, str] = {}

        # 确保目录存在
        os.makedirs(cache_dir, exist_ok=True)

        # 加载缓存
        self.load()

    def load(self):
        """加载缓存"""
        try:
            if os.path.exists(self.cache_file):
                with open(self.cache_file, "r", encoding="utf-8") as f:
                    self.cache = json.load(f)
                print(f"加载封面缓存，大小: {len(self.cache)}")
        except Exception as e:
            print(f"加载封面缓存失败: {e}")
            self.cache = {}

    def save(self):
        """保存缓存"""
        try:
            with open(self.cache_file, "w", encoding="utf-8") as f:
                json.dump(self.cache, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存封面缓存失败: {e}")

    def get(self, album_id: int) -> Optional[str]:
        """获取封面URL"""
        cache_key = str(album_id)
        return self.cache.get(cache_key)

    def set(self, album_id: int, cover_url: str):
        """设置封面URL"""
        cache_key = str(album_id)
        self.cache[cache_key] = cover_url
        self.save()

    def clear(self):
        """清空缓存"""
        self.cache = {}
        self.save()
        print("封面缓存已清空")
