# -*- coding: utf-8 -*-
"""
JM 漫画爬虫服务。
"""

import concurrent.futures
import io
import json
import os
import re
import shutil
import time
from concurrent.futures import ThreadPoolExecutor
from typing import Dict, List, Optional

import jmcomic
import requests
import yaml
from PIL import Image


class JMCrawler:
    """JM 漫画爬虫服务。"""

    def __init__(self):
        self.base_dir = os.environ.get(
            "BASE_DIR",
            os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            ),
        )
        self.temp_cache = os.environ.get(
            "TEMP_CACHE_DIR", os.path.join(self.base_dir, "TempCache")
        )

        root_option_file = os.path.join(self.base_dir, "jm_option.yml")
        backend_option_file = os.path.join(self.base_dir, "backend", "jm_option.yml")
        self.option_file = (
            root_option_file if os.path.exists(root_option_file) else backend_option_file
        )

        os.makedirs(self.temp_cache, exist_ok=True)
        self._ensure_option_file()

        self.jm_option = jmcomic.JmOption.from_file(self.option_file)
        self.cover_cache_file = os.path.join(self.temp_cache, "cover_cache.json")
        self.cover_cache = self._load_cover_cache()

    def _build_default_option_content(self) -> Dict:
        return {
            "client": {
                "retry_times": 5,
                "domain": [
                    "www.cdnhth.club",
                    "www.cdngwc.cc",
                    "www.cdngwc.net",
                    "www.cdngwc.club",
                    "www.cdn-mspjmapiproxy.xyz",
                ],
                "headers": {
                    "User-Agent": (
                        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                        "AppleWebKit/537.36 (KHTML, like Gecko) "
                        "Chrome/120.0.0.0 Safari/537.36"
                    ),
                    "Accept": (
                        "text/html,application/xhtml+xml,application/xml;q=0.9,"
                        "image/webp,*/*;q=0.8"
                    ),
                    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
                    "Accept-Encoding": "gzip, deflate, br",
                    "Connection": "keep-alive",
                },
            },
            "download": {
                "cache": True,
                "image": {"decode": True, "suffix": ".jpg"},
                "threading": {"batch_count": 30, "max_workers": 5},
            },
            "plugins": {
                "after_photo": [
                    {
                        "plugin": "img2pdf",
                        "kwargs": {
                            "img_dir": ".",
                            "pdf_dir": ".",
                            "filename_rule": "Pid",
                        },
                    }
                ]
            },
            "dir_rule": {
                "rule": "{Aid}/{Pid}",
                "base_dir": os.path.join(self.base_dir, "TempCache", "downloads"),
            },
        }

    def _merge_option_content(self, current: Dict, defaults: Dict) -> Dict:
        merged = dict(current)

        for key, default_value in defaults.items():
            current_value = merged.get(key)
            if key not in merged:
                merged[key] = default_value
            elif isinstance(current_value, dict) and isinstance(default_value, dict):
                merged[key] = self._merge_option_content(current_value, default_value)

        return merged

    def _write_option_file(self, option_content: Dict):
        os.makedirs(os.path.dirname(self.option_file), exist_ok=True)
        with open(self.option_file, "w", encoding="utf-8") as f:
            yaml.safe_dump(
                option_content,
                f,
                default_flow_style=False,
                allow_unicode=True,
                sort_keys=False,
            )

    def _ensure_option_file(self):
        """Ensure jm_option.yml exists without overwriting user settings."""
        default_content = self._build_default_option_content()

        if not os.path.exists(self.option_file):
            self._write_option_file(default_content)
            return

        try:
            with open(self.option_file, "r", encoding="utf-8") as f:
                current_content = yaml.safe_load(f) or {}
            if not isinstance(current_content, dict):
                raise ValueError("jm_option.yml must contain a YAML mapping")
        except Exception as exc:
            backup_file = f"{self.option_file}.bak"
            try:
                shutil.copy2(self.option_file, backup_file)
                print(f"jm_option.yml 无法解析，已备份到 {backup_file}")
            except Exception as backup_error:
                print(f"备份 jm_option.yml 失败: {backup_error}")

            print(f"重建默认 jm_option.yml: {exc}")
            self._write_option_file(default_content)
            return

        merged_content = self._merge_option_content(current_content, default_content)
        if merged_content != current_content:
            self._write_option_file(merged_content)

    def _build_option(self):
        return jmcomic.create_option_by_file(self.option_file)

    def _build_client(self):
        return self._build_option().build_jm_client()

    def _parse_count(self, value) -> int:
        if value is None:
            return 0
        if isinstance(value, bool):
            return int(value)
        if isinstance(value, (int, float)):
            return int(value)

        text = str(value).strip()
        if not text:
            return 0

        text = text.replace(",", "").replace(" ", "").lower()
        match = re.search(r"(\d+(?:\.\d+)?)(亿|万|k|m|b|w)?", text)
        if not match:
            return 0

        number = float(match.group(1))
        unit = match.group(2) or ""
        multiplier = {
            "w": 10_000,
            "k": 1_000,
            "m": 1_000_000,
            "b": 1_000_000_000,
            "万": 10_000,
            "亿": 100_000_000,
        }.get(unit, 1)

        return int(number * multiplier)

    def _load_cover_cache(self) -> Dict[str, str]:
        try:
            if os.path.exists(self.cover_cache_file):
                with open(self.cover_cache_file, "r", encoding="utf-8") as f:
                    cache = json.load(f)
                print(f"加载封面缓存，数量: {len(cache)}")
                return cache
        except Exception as e:
            print(f"加载封面缓存失败: {e}")
        return {}

    def _save_cover_cache(self):
        try:
            with open(self.cover_cache_file, "w", encoding="utf-8") as f:
                json.dump(self.cover_cache, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存封面缓存失败: {e}")

    def get_comic_info(self, album_id: int) -> Optional[Dict]:
        """获取漫画详细信息。"""
        try:
            client = self._build_client()
            album = client.get_album_detail(album_id)
            if not album:
                return None

            comic_info = {
                "id": album_id,
                "title": getattr(album, "title", "Unknown"),
                "author": getattr(album, "author", "Unknown"),
                "cover": "",
                "tags": list(getattr(album, "tags", []) or []),
                "description": getattr(album, "description", ""),
                "favorites": self._parse_count(getattr(album, "likes", 0)),
                "pages": getattr(album, "page_count", 0),
                "scramble_id": getattr(album, "scramble_id", ""),
                "works": list(getattr(album, "works", []) or []),
                "actors": list(getattr(album, "actors", []) or []),
                "keywords": list(getattr(album, "keywords", []) or []),
            }

            cover_url = self.get_cover_url(album_id)
            if cover_url:
                comic_info["cover"] = cover_url
                cover_path = self._download_cover(cover_url, album_id)
                if cover_path:
                    comic_info["cover_local"] = cover_path

            return comic_info

        except Exception as e:
            print(f"获取漫画信息失败 {album_id}: {e}")
            return None

    def get_cover_url(self, album_id: int) -> str:
        """获取封面 URL。"""
        cache_key = str(album_id)
        if cache_key in self.cover_cache:
            print(f"从缓存获取封面 {album_id}")
            return self.cover_cache[cache_key]

        try:
            client = self._build_client()
            domain_list = getattr(client, "domain_list", []) or []
            domain = domain_list[0] if domain_list else "www.cdnhth.club"
            cover_url = f"https://{domain}/media/albums/{album_id}.jpg"
            self.cover_cache[cache_key] = cover_url
            self._save_cover_cache()
            return cover_url
        except Exception as e:
            print(f"获取封面 URL 失败 {album_id}: {e}")
            return ""

    def _extract_search_result(self, album) -> Optional[Dict]:
        comic_info = {}

        if isinstance(album, tuple) and len(album) >= 2:
            album_id = album[0]
            info_dict = album[1]
            if not isinstance(info_dict, dict):
                return None

            favorites_raw = 0
            for key in (
                "favorites",
                "likes",
                "like",
                "favourites",
                "favorite",
                "fav",
            ):
                if key in info_dict and info_dict[key] is not None:
                    favorites_raw = info_dict[key]
                    break

            comic_info = {
                "id": int(album_id) if album_id and str(album_id).isdigit() else 0,
                "title": info_dict.get("name", "未知标题"),
                "author": info_dict.get("author", "未知作者"),
                "cover": "",
                "favorites": self._parse_count(favorites_raw),
                "tags": list(info_dict.get("tags", []) or [])[:5],
                "description": (info_dict.get("description") or "")[:100],
            }
        elif hasattr(album, "__dict__"):
            favorites_raw = (
                getattr(album, "favorites", None)
                if getattr(album, "favorites", None) is not None
                else getattr(album, "likes", 0)
            )
            comic_info = {
                "id": getattr(album, "id", 0),
                "title": getattr(album, "title", None)
                or getattr(album, "name", "未知标题"),
                "author": getattr(album, "author", "未知作者"),
                "cover": "",
                "favorites": self._parse_count(favorites_raw),
                "tags": list(getattr(album, "tags", []) or [])[:5],
                "description": (getattr(album, "description", None) or "")[:100],
            }
        elif isinstance(album, dict):
            favorites_raw = 0
            for key in (
                "favorites",
                "likes",
                "like",
                "favourites",
                "favorite",
                "fav",
            ):
                if key in album and album[key] is not None:
                    favorites_raw = album[key]
                    break

            comic_info = {
                "id": album.get("id", 0),
                "title": album.get("name", album.get("title", "未知标题")),
                "author": album.get("author", "未知作者"),
                "cover": "",
                "favorites": self._parse_count(favorites_raw),
                "tags": list(album.get("tags", []) or [])[:5],
                "description": (album.get("description") or "")[:100],
            }

        if not comic_info or not comic_info.get("id"):
            return None

        comic_info["needs_cover"] = True
        comic_info["needs_detail"] = True
        return comic_info

    def _fetch_search_detail(self, client, album_id: int) -> Optional[Dict]:
        try:
            detail = client.get_album_detail(album_id)
            if not detail:
                return None

            return {
                "id": album_id,
                "favorites": self._parse_count(getattr(detail, "likes", 0)),
                "author": str(getattr(detail, "author", "未知作者")),
                "tags": list(getattr(detail, "tags", []) or [])[:5],
                "description": (getattr(detail, "description", None) or "")[:100],
                "pages": getattr(detail, "page_count", 0),
            }
        except Exception as e:
            print(f"获取搜索详情失败 {album_id}: {e}")
            return None

    def get_search_result_details(self, album_ids: List[int]) -> Dict[str, Dict]:
        cleaned_ids = []
        seen_ids = set()

        for album_id in album_ids:
            try:
                parsed_id = int(album_id)
            except (TypeError, ValueError):
                continue

            if parsed_id <= 0 or parsed_id in seen_ids:
                continue

            seen_ids.add(parsed_id)
            cleaned_ids.append(parsed_id)

        if not cleaned_ids:
            return {}

        client = self._build_client()
        details = {}
        max_workers = min(6, len(cleaned_ids))

        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(self._fetch_search_detail, client, album_id): album_id
                for album_id in cleaned_ids
            }

            for future in concurrent.futures.as_completed(futures):
                album_id = futures[future]
                try:
                    detail = future.result()
                except Exception as e:
                    print(f"处理搜索详情失败 {album_id}: {e}")
                    continue

                if detail:
                    details[str(album_id)] = detail

        return details

    def _search_site(
        self,
        client,
        keyword: str,
        page: int,
        order_by: str,
        time: str,
        category: str,
        sub_category,
    ):
        """
        兼容 jmcomic 新旧版本的站内搜索接口。
        新版把 main_tag 提升为了必填参数，并提供了 search_site 包装方法。
        """
        search_kwargs = {
            "page": page,
            "order_by": order_by,
            "time": time,
            "category": category,
            "sub_category": sub_category,
        }

        if hasattr(client, "search_site"):
            return client.search_site(keyword, **search_kwargs)

        try:
            return client.search(keyword, **search_kwargs)
        except TypeError as e:
            if "main_tag" not in str(e):
                raise
            return client.search(
                keyword,
                page,
                0,
                order_by,
                time,
                category,
                sub_category,
            )

    def search_by_keyword(
        self, keyword: str, sort_order: str = "desc", page: int = 1
    ) -> List[Dict]:
        """轻量搜索，详情按需补充。"""
        try:
            sort_order = (sort_order or "desc").strip().lower()
            if sort_order not in ("asc", "desc"):
                sort_order = "desc"
            page = max(1, int(page or 1))

            client = self._build_client()

            try:
                search_results = self._search_site(
                    client,
                    keyword,
                    page=page,
                    order_by="mr",
                    time="a",
                    category="0",
                    sub_category=None,
                )
                print(f"搜索成功，结果类型: {type(search_results)}")
            except Exception as e:
                print(f"搜索失败: {e}")
                search_results = None

            if not search_results:
                return []

            try:
                if hasattr(search_results, "album_info_list"):
                    albums = getattr(search_results, "album_info_list", [])
                elif hasattr(search_results, "content"):
                    albums = list(getattr(search_results, "content", []))
                elif hasattr(search_results, "__iter__") and not isinstance(
                    search_results, (str, bytes)
                ):
                    albums = list(search_results)
                else:
                    albums = [search_results] if search_results else []
            except Exception as e:
                print(f"获取专辑列表失败: {e}")
                albums = []

            if not albums:
                try:
                    tag_results = client.search_tag(keyword, page)
                    if (
                        tag_results
                        and hasattr(tag_results, "__iter__")
                        and not isinstance(tag_results, (str, bytes))
                    ):
                        albums = list(tag_results)
                except Exception as e:
                    print(f"标签搜索失败: {e}")

            comics = []
            for album in albums:
                try:
                    comic_info = self._extract_search_result(album)
                    if comic_info:
                        comics.append(comic_info)
                except Exception as e:
                    print(f"处理专辑信息失败: {e}, album: {album}")

            comics.sort(
                key=lambda x: self._parse_count(x.get("favorites", 0)),
                reverse=(sort_order == "desc"),
            )
            return comics

        except Exception as e:
            print(f"关键词搜索失败 '{keyword}': {str(e)}")
            import traceback

            traceback.print_exc()
            return []

    def download_comic(self, album_id: int, progress_callback=None) -> bool:
        """下载漫画。"""
        try:
            if progress_callback:
                progress_callback(0, "starting", "开始下载...")

            download_dir = os.path.join(
                self.base_dir, "TempCache", "downloads", str(album_id)
            )
            os.makedirs(download_dir, exist_ok=True)

            if progress_callback:
                progress_callback(10, "preparing", "准备下载环境...")

            option = self._build_option()

            if progress_callback:
                progress_callback(30, "downloading", "正在获取漫画信息...")

            try:
                jmcomic.download_album(
                    album_id,
                    option=option,
                    callback=None,
                    check_exception=False,
                )

                if progress_callback:
                    progress_callback(80, "downloading", "漫画下载中...")

                time.sleep(2)
            except Exception as e:
                print(f"JMComic 下载失败: {e}")
                return self._simple_download(album_id, progress_callback)

            if progress_callback:
                progress_callback(95, "processing", "下载完成，正在验证文件...")

            if not os.path.exists(download_dir):
                if progress_callback:
                    progress_callback(0, "error", "下载失败：目录未创建")
                return False

            files = os.listdir(download_dir)
            if not files:
                if progress_callback:
                    progress_callback(0, "error", "下载失败：目录为空")
                return False

            print(f"漫画 {album_id} 下载成功，文件数: {len(files)}")
            if progress_callback:
                progress_callback(100, "completed", f"下载完成，共 {len(files)} 个文件")
            return True

        except Exception as e:
            print(f"下载漫画失败 {album_id}: {e}")
            import traceback

            traceback.print_exc()
            if progress_callback:
                progress_callback(0, "error", f"下载失败: {str(e)}")
            return False

    def _simple_download(self, album_id: int, progress_callback=None) -> bool:
        """备用下载流程。"""
        try:
            if progress_callback:
                progress_callback(40, "downloading", "使用备用方式下载...")

            option = self._build_option()
            client = option.build_jm_client()

            album = client.get_album_detail(album_id)
            if not album:
                print(f"无法获取专辑 {album_id} 详情")
                return False

            if progress_callback:
                progress_callback(60, "downloading", "获取图片列表...")

            photo_detail = client.get_photo_detail(album_id)
            if not photo_detail:
                print(f"无法获取照片详情 {album_id}")
                return False

            if progress_callback:
                progress_callback(80, "downloading", "下载漫画内容...")

            downloader = jmcomic.JmDownloader(option)
            downloader.download_album(album_id)

            if progress_callback:
                progress_callback(95, "processing", "下载完成")

            return True

        except Exception as e:
            print(f"备用下载失败 {album_id}: {e}")
            return False

    def _download_cover(self, cover_url: str, album_id: int) -> Optional[str]:
        """下载封面图片。"""
        try:
            headers = {
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36"
                )
            }
            response = requests.get(cover_url, headers=headers, timeout=30)
            response.raise_for_status()

            cover_filename = f"cover_{album_id}.jpg"
            cover_path = os.path.join(self.temp_cache, cover_filename)

            image = Image.open(io.BytesIO(response.content))
            if image.mode == "RGBA":
                rgb_image = Image.new("RGB", image.size, (255, 255, 255))
                rgb_image.paste(image, mask=image.split()[3])
                image = rgb_image

            image.save(cover_path, "JPEG", quality=85)
            return cover_path

        except Exception as e:
            print(f"下载封面失败 {album_id}: {e}")
            return None
