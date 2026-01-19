# -*- coding: utf-8 -*-
"""
JM漫画爬虫服务
基于JMComic-Crawler-Python实现
"""

import os
import yaml
import jmcomic
from typing import Dict, List, Optional
import requests
from PIL import Image
import io


class JMCrawler:
    """JM漫画爬虫服务"""

    def __init__(self):
        self.base_dir = "E:\\JMComicReaderProject"
        self.temp_cache = os.path.join(self.base_dir, "TempCache")
        self.option_file = os.path.join(self.base_dir, "backend", "jm_option.yml")

        # 确保目录存在
        os.makedirs(self.temp_cache, exist_ok=True)

        # 创建配置文件
        self._create_option_file()

        # 初始化JM配置
        self.jm_option = jmcomic.JmOption.from_file(self.option_file)

    def _create_option_file(self):
        """创建JM爬虫配置文件"""
        option_content = {
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
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
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
                "after_album": [
                    {
                        "plugin": "img2pdf",
                        "kwargs": {
                            "img_dir": "stock",
                            "pdf_dir": "pdf",
                            "filename_rule": "Aid",
                        },
                    }
                ]
            },
            "dir_rule": {
                "rule": "{Aid}",
                "base_dir": os.path.join(self.base_dir, "TempCache", "downloads"),
            },
        }

        os.makedirs(os.path.dirname(self.option_file), exist_ok=True)
        with open(self.option_file, "w", encoding="utf-8") as f:
            yaml.dump(option_content, f, default_flow_style=False, allow_unicode=True)

    def get_comic_info(self, album_id: int) -> Optional[Dict]:
        """
        获取漫画详细信息

        Args:
            album_id: JM漫画ID

        Returns:
            漫画信息字典，失败返回None
        """
        try:
            # 使用JMComic获取专辑信息
            option = jmcomic.create_option_by_file(self.option_file)
            client = option.build_jm_client()
            album = client.get_album_detail(album_id)
            if not album:
            return None

    def _load_cover_cache(self):
        """加载封面缓存"""
        try:
            if os.path.exists(self.cover_cache_file):
                import json
                with open(self.cover_cache_file, 'r', encoding='utf-8') as f:
                    self.cover_cache = json.load(f)
                print(f"加载封面缓存，大小: {len(self.cover_cache)}")
        except Exception as e:
            print(f"加载封面缓存失败: {e}")
            self.cover_cache = {}

    def _save_cover_cache(self):
        """保存封面缓存"""
        try:
            import json
            with open(self.cover_cache_file, 'w', encoding='utf-8') as f:
                json.dump(self.cover_cache, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存封面缓存失败: {e}")

    def get_cover_url(self, album_id: int) -> str:
        """获取封面URL（带缓存）"""
        # 检查缓存
        cache_key = str(album_id)
        if cache_key in self.cover_cache:
            print(f"从缓存获取封面 {album_id}")
            return self.cover_cache[cache_key]
        
        # 缓存未命中，获取封面
        try:
            print(f"获取封面 {album_id}（缓存未命中）")
            # 获取照片详情
            option = jmcomic.create_option_by_file(self.option_file)
            client = option.build_jm_client()
            photo_detail = client.get_photo_detail(album_id)
            
            if photo_detail and hasattr(photo_detail, 'page_arr') and photo_detail.page_arr:
                first_page = photo_detail.page_arr[0]
                if isinstance(first_page, str) and first_page:
                    # 构建完整URL
                    domain = getattr(photo_detail, 'data_original_domain', 'www.cdnhth.club')
                    cover_url = f"https://{domain}/media/photos/{album_id}/{first_page}"
                    
                    # 保存到缓存
                    self.cover_cache[cache_key] = cover_url
                    self._save_cover_cache()
                    
                    return cover_url
        except Exception as e:
            print(f"获取封面URL失败 {album_id}: {e}")
        
        return ""

            # 提取关键信息
            comic_info = {
                "id": album_id,
                "title": getattr(album, "title", "Unknown"),
                "author": getattr(album, "author", "Unknown"),
                "cover": "",  # 初始为空，后面尝试获取
                "tags": getattr(album, "tags", []),
                "description": getattr(album, "description", ""),
                "favorites": getattr(album, "likes", 0),
                "pages": getattr(album, "page_count", 0),
                "scramble_id": getattr(album, "scramble_id", ""),
                "works": getattr(album, "works", []),
                "actors": getattr(album, "actors", []),
                "keywords": getattr(album, "keywords", []),
            }

            # 尝试获取封面图片 - 通过获取照片详情
            try:
                # 获取照片详情
                photo_detail = client.get_photo_detail(album_id)
                if (
                    photo_detail
                    and hasattr(photo_detail, "page_arr")
                    and photo_detail.page_arr
                ):
                    # page_arr包含图片文件名
                    print(
                        f"专辑 {album_id} 有page_arr，长度: {len(photo_detail.page_arr)}"
                    )

                    # 获取第一张图片的文件名
                    first_page = photo_detail.page_arr[0]
                    if isinstance(first_page, str) and first_page:
                        # 构建完整URL
                        # 需要获取域名和查询参数
                        domain = getattr(
                            photo_detail, "data_original_domain", "www.cdnhth.club"
                        )
                        query_params = getattr(
                            photo_detail, "data_original_query_params", {}
                        )

                        # 构建查询字符串
                        query_str = ""
                        if query_params:
                            query_str = "?" + "&".join(
                                [f"{k}={v}" for k, v in query_params.items()]
                            )

                        # 构建完整URL
                        comic_info["cover"] = (
                            f"https://{domain}/media/photos/{album_id}/{first_page}{query_str}"
                        )
                        print(f"封面URL: {comic_info['cover']}")
            except Exception as e:
                print(f"获取封面失败 {album_id}: {e}")

            # 下载封面图片到缓存
            if comic_info["cover"]:
                cover_path = self._download_cover(comic_info["cover"], album_id)
                if cover_path:
                    comic_info["cover_local"] = cover_path

            return comic_info

        except Exception as e:
            print(f"获取漫画信息失败 {album_id}: {e}")
            return None

    def search_by_keyword(self, keyword: str, sort_order: str = "desc") -> List[Dict]:
        """
        关键词搜索漫画

        Args:
            keyword: 搜索关键词
            sort_order: 排序方式，'desc'降序，'asc'升序

        Returns:
            漫画列表
        """
        try:
            # 使用JMComic客户端搜索
            option = jmcomic.create_option_by_file(self.option_file)
            client = option.build_jm_client()

            # 使用客户端直接搜索
            try:
                # 尝试使用客户端的搜索功能
                search_results = client.search(keyword, 1, 0, "mr", "all", "all", None)
                print(f"搜索成功，找到结果类型: {type(search_results)}")
            except Exception as e:
                print(f"搜索失败: {e}")
                # 如果搜索失败，返回空列表
                search_results = None

            if not search_results:
                return []

            # 转换结果格式
            comics = []
            albums = []

            # 安全地获取专辑列表
            try:
                if search_results:
                    # 尝试不同的属性访问方式
                    if hasattr(search_results, "album_info_list"):
                        albums = getattr(search_results, "album_info_list", [])
                    elif hasattr(search_results, "content"):
                        # JmSearchPage对象，使用content属性
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

            # 如果没有结果，尝试其他搜索方法
            if not albums:
                try:
                    # 尝试标签搜索
                    tag_results = client.search_tag(keyword, 1)
                    if (
                        tag_results
                        and hasattr(tag_results, "__iter__")
                        and not isinstance(tag_results, (str, bytes))
                    ):
                        albums = list(tag_results)
                except:
                    pass

            for album in albums:
                comic_info = {}

                try:
                    # 处理不同的数据结构
                    if isinstance(album, tuple) and len(album) >= 2:
                        # 元组格式: (id, info_dict)
                        album_id = album[0]
                        info_dict = album[1]

                        # 确保info_dict是字典
                        if isinstance(info_dict, dict):
                            # 从info_dict提取信息
                            comic_info = {
                                "id": int(album_id)
                                if album_id and str(album_id).isdigit()
                                else 0,
                                "title": info_dict.get("name", "未知标题"),
                                "author": info_dict.get("author", "未知作者"),
                                "cover": "",  # 初始为空，后面尝试获取
                                "favorites": info_dict.get("likes", 0) or 0,
                                "tags": info_dict.get("tags", [])[:5],
                                "description": (info_dict.get("description") or "")[
                                    :100
                                ],
                            }

                            # 不立即获取封面，使用占位符
                            # 封面将在前端需要时通过单独的API获取
                            comic_info["cover"] = ""  # 空字符串，表示需要延迟加载
                            comic_info["has_cover"] = False  # 标记需要加载封面
                        else:
                            # info_dict不是字典，可能是字符串或其他类型
                            print(
                                f"警告: album[1]不是字典, 类型: {type(info_dict)}, 值: {info_dict}"
                            )
                            continue
                    elif hasattr(album, "__dict__"):
                        # 对象格式
                        comic_info = {
                            "id": getattr(album, "id", 0),
                            "title": getattr(album, "title", None)
                            or getattr(album, "name", "未知标题"),
                            "author": getattr(album, "author", "未知作者"),
                            "cover": getattr(album, "cover", ""),
                            "favorites": getattr(album, "favorites", 0)
                            or getattr(album, "likes", 0),
                            "tags": getattr(album, "tags", [])[:5]
                            if hasattr(album, "tags")
                            else [],
                            "description": (getattr(album, "description", None) or "")[
                                :100
                            ],
                        }
                    elif isinstance(album, dict):
                        # 直接是字典格式
                        comic_info = {
                            "id": album.get("id", 0),
                            "title": album.get("name", album.get("title", "未知标题")),
                            "author": album.get("author", "未知作者"),
                            "cover": album.get("image", album.get("cover", "")),
                            "favorites": album.get("favorites", album.get("likes", 0)),
                            "tags": album.get("tags", [])[:5],
                            "description": (album.get("description") or "")[:100],
                        }
                    else:
                        # 其他格式，跳过
                        print(
                            f"警告: 未知的album格式, 类型: {type(album)}, 值: {album}"
                        )
                        continue

                    comics.append(comic_info)

                except Exception as e:
                    print(f"处理专辑信息失败: {e}, album: {album}")
                    continue

            # 按收藏量排序
            comics.sort(key=lambda x: x["favorites"], reverse=(sort_order == "desc"))

            return comics

        except Exception as e:
            print(f"关键词搜索失败 '{keyword}': {str(e)}")
            import traceback

            traceback.print_exc()
            return []

    def download_comic(self, album_id: int, progress_callback=None) -> bool:
        """
        下载漫画

        Args:
            album_id: JM漫画ID
            progress_callback: 进度回调函数

        Returns:
            是否下载成功
        """
        try:
            if progress_callback:
                progress_callback(0, "starting", "开始下载...")

            # 设置下载目录
            download_dir = os.path.join(
                self.base_dir, "TempCache", "downloads", str(album_id)
            )
            os.makedirs(download_dir, exist_ok=True)

            # 更新配置中的下载目录
            self.jm_option.dir_rule.base_dir = download_dir

            if progress_callback:
                progress_callback(10, "downloading", "正在获取漫画信息...")

            # 下载专辑
            jmcomic.download_album([album_id], option=self.jm_option)

            if progress_callback:
                progress_callback(90, "processing", "正在处理文件...")

            # 检查是否下载成功
            if os.path.exists(download_dir) and any(os.listdir(download_dir)):
                if progress_callback:
                    progress_callback(100, "completed", "下载完成")
                return True
            else:
                if progress_callback:
                    progress_callback(0, "error", "下载失败")
                return False

        except Exception as e:
            print(f"下载漫画失败 {album_id}: {e}")
            if progress_callback:
                progress_callback(0, "error", f"下载失败: {str(e)}")
            return False

    def _download_cover(self, cover_url: str, album_id: int) -> Optional[str]:
        """
        下载封面图片

        Args:
            cover_url: 封面图片URL
            album_id: 漫画ID

        Returns:
            本地文件路径，失败返回None
        """
        try:
            # 发送请求下载图片
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
            }
            response = requests.get(cover_url, headers=headers, timeout=30)
            response.raise_for_status()

            # 保存图片
            cover_filename = f"cover_{album_id}.jpg"
            cover_path = os.path.join(self.temp_cache, cover_filename)

            # 处理图片（如果需要）
            image = Image.open(io.BytesIO(response.content))

            # 转换为RGB模式（如果是RGBA）
            if image.mode == "RGBA":
                rgb_image = Image.new("RGB", image.size, (255, 255, 255))
                rgb_image.paste(image, mask=image.split()[3])
                image = rgb_image

            # 保存
            image.save(cover_path, "JPEG", quality=85)

            return cover_path

        except Exception as e:
            print(f"下载封面失败 {album_id}: {e}")
            return None

    def cleanup_cache(self):
        """清理缓存"""
        try:
            import shutil

            if os.path.exists(self.temp_cache):
                shutil.rmtree(self.temp_cache)
                os.makedirs(self.temp_cache, exist_ok=True)
            return True
        except Exception as e:
            print(f"清理缓存失败: {e}")
            return False
