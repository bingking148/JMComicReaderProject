# -*- coding: utf-8 -*-
"""
漫画管理器
负责已下载漫画的管理和阅读功能
"""

import os
import json
import shutil
from typing import List, Dict, Optional
from datetime import datetime
import jmcomic


class ComicManager:
    """漫画管理器"""

    def __init__(self):
        # 使用环境变量或默认路径
        self.base_dir = os.environ.get(
            "BASE_DIR",
            os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            ),
        )
        self.downloaded_dir = os.environ.get(
            "DOWNLOAD_DIR", os.path.join(self.base_dir, "DownloadedComics")
        )
        self.db_file = os.path.join(self.base_dir, "backend", "comics.db")

        # 确保目录存在
        os.makedirs(self.downloaded_dir, exist_ok=True)
        os.makedirs(os.path.dirname(self.db_file), exist_ok=True)

        # 初始化数据库
        self._init_database()

    def _init_database(self):
        """初始化数据库"""
        import sqlite3

        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()

        # 创建已下载漫画表
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS downloaded_comics (
                id INTEGER PRIMARY KEY,
                jm_id INTEGER UNIQUE NOT NULL,
                title TEXT NOT NULL,
                author TEXT,
                tags TEXT,
                description TEXT,
                favorites INTEGER DEFAULT 0,
                pages INTEGER DEFAULT 0,
                cover_path TEXT,
                comic_path TEXT,
                download_time DATETIME DEFAULT CURRENT_TIMESTAMP,
                last_read_time DATETIME,
                read_progress INTEGER DEFAULT 0,
                file_size INTEGER DEFAULT 0
            )
        """)

        conn.commit()
        conn.close()

    def is_comic_downloaded(self, jm_id: int) -> bool:
        """检查漫画是否已下载"""
        import sqlite3

        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()

        cursor.execute("SELECT id FROM downloaded_comics WHERE jm_id = ?", (jm_id,))
        result = cursor.fetchone()

        conn.close()

        # 同时检查文件是否存在
        if result:
            comic_dir = os.path.join(self.downloaded_dir, f"{jm_id}_")
            for dirname in os.listdir(self.downloaded_dir):
                if dirname.startswith(f"{jm_id}_"):
                    return True

        return False

    def add_downloaded_comic(self, jm_id: int, comic_info: dict):
        """添加已下载漫画到数据库"""
        import sqlite3

        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()

        try:
            # 找到漫画目录
            comic_dir = None
            for dirname in os.listdir(self.downloaded_dir):
                if dirname.startswith(f"{jm_id}_"):
                    comic_dir = os.path.join(self.downloaded_dir, dirname)
                    break

            if not comic_dir:
                return False

            # 查找PDF文件
            pdf_path = None
            for filename in os.listdir(comic_dir):
                if filename.endswith(".pdf"):
                    pdf_path = os.path.join(comic_dir, filename)
                    break

            # 查找封面
            cover_path = None
            if os.path.exists(os.path.join(comic_dir, "cover.jpg")):
                cover_path = os.path.join(comic_dir, "cover.jpg")

            # 计算文件总大小
            file_size = 0
            try:
                for root, dirs, files in os.walk(comic_dir):
                    for filename in files:
                        file_path = os.path.join(root, filename)
                        if os.path.isfile(file_path):
                            file_size += os.path.getsize(file_path)
            except Exception as e:
                print(f"计算文件大小失败: {e}")
                file_size = 0

            # 插入数据库
            cursor.execute(
                """
                INSERT OR REPLACE INTO downloaded_comics 
                (jm_id, title, author, tags, description, favorites, pages, cover_path, comic_path, file_size)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
                (
                    jm_id,
                    comic_info.get("title", ""),
                    comic_info.get("author", ""),
                    ",".join(comic_info.get("tags", [])),
                    comic_info.get("description", ""),
                    comic_info.get("favorites", 0),
                    comic_info.get("pages", 0),
                    cover_path,
                    pdf_path,
                    file_size,
                ),
            )

            conn.commit()
            return True

        except Exception as e:
            print(f"添加已下载漫画失败 {jm_id}: {e}")
            return False
        finally:
            conn.close()

    def get_downloaded_comics(self) -> List[Dict]:
        """获取已下载漫画列表"""
        import sqlite3

        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()

        try:
            cursor.execute("""
                SELECT jm_id, title, author, tags, favorites, pages,
                       download_time, last_read_time, read_progress, file_size
                FROM downloaded_comics
                ORDER BY download_time DESC
            """)

            comics = []
            for row in cursor.fetchall():
                (
                    jm_id,
                    title,
                    author,
                    tags,
                    favorites,
                    pages,
                    download_time,
                    last_read_time,
                    read_progress,
                    file_size,
                ) = row

                # 检查文件是否存在
                comic_dir = None
                for dirname in os.listdir(self.downloaded_dir):
                    if dirname.startswith(f"{jm_id}_"):
                        comic_dir = os.path.join(self.downloaded_dir, dirname)
                        break

                if comic_dir:
                    # 查找封面
                    cover_path = None
                    if os.path.exists(os.path.join(comic_dir, "cover.jpg")):
                        cover_path = os.path.join(comic_dir, "cover.jpg")

                    comics.append(
                        {
                            "id": jm_id,
                            "title": title,
                            "author": author,
                            "tags": tags.split(",") if tags else [],
                            "favorites": favorites,
                            "pages": pages,
                            "cover_path": cover_path,
                            "download_time": download_time,
                            "last_read_time": last_read_time,
                            "read_progress": read_progress,
                            "file_size": file_size,
                        }
                    )

            return comics

        except Exception as e:
            print(f"获取已下载漫画列表失败: {e}")
            return []
        finally:
            conn.close()

    def get_comic_path(self, jm_id: int) -> Optional[str]:
        """获取漫画路径"""
        for dirname in os.listdir(self.downloaded_dir):
            if dirname.startswith(f"{jm_id}_"):
                comic_dir = os.path.join(self.downloaded_dir, dirname)

                # 查找PDF文件
                for filename in os.listdir(comic_dir):
                    if filename.endswith(".pdf"):
                        return os.path.join(comic_dir, filename)

                # 如果没有PDF，查找图片目录
                # 先检查是否有以jm_id命名的子目录
                subdir_path = os.path.join(comic_dir, str(jm_id))
                if os.path.exists(subdir_path) and os.path.isdir(subdir_path):
                    return subdir_path

                # 如果没有子目录，返回漫画目录本身
                return comic_dir

        return None

    def get_comic_pages(self, jm_id: int) -> int:
        """获取漫画页数"""
        import sqlite3

        # 先从数据库获取
        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()
        db_pages = 0

        try:
            cursor.execute(
                "SELECT pages FROM downloaded_comics WHERE jm_id = ?", (jm_id,)
            )
            result = cursor.fetchone()
            db_pages = result[0] if result else 0
        finally:
            conn.close()

        # 如果数据库中有页数，返回数据库值
        if db_pages > 0:
            return db_pages

        # 否则，从文件系统计算
        comic_path = self.get_comic_path(jm_id)
        if not comic_path or not os.path.exists(comic_path):
            return 0

        # 如果路径是文件（PDF），尝试获取对应的目录
        if os.path.isfile(comic_path):
            comic_dir = os.path.dirname(comic_path)
        else:
            comic_dir = comic_path

        # 计算图片文件数量
        image_extensions = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp"}
        page_count = 0

        if os.path.exists(comic_dir) and os.path.isdir(comic_dir):
            for filename in os.listdir(comic_dir):
                file_ext = os.path.splitext(filename)[1].lower()
                if file_ext in image_extensions:
                    page_count += 1

        return page_count

    def _get_chapter_order_from_jm(self, jm_id: int) -> Optional[List[str]]:
        """
        从JM网站获取章节顺序

        Args:
            jm_id: 漫画ID

        Returns:
            章节ID列表，如果获取失败则返回None
        """
        try:
            # 使用JMComic客户端获取专辑详情
            client = jmcomic.JmOption.default().new_jm_client()
            album_detail = client.get_album_detail(jm_id)

            # 提取章节顺序
            chapter_order = []
            for photo in album_detail:
                chapter_order.append(str(photo.photo_id))

            return chapter_order
        except Exception as e:
            print(f"从JM获取章节顺序失败 {jm_id}: {e}")
            return None

    def get_comic_chapters(self, jm_id: int) -> List[Dict]:
        """获取漫画章节列表"""
        chapters = []

        try:
            # 查找漫画目录
            comic_dir = None
            for dirname in os.listdir(self.downloaded_dir):
                if dirname.startswith(f"{jm_id}_"):
                    comic_dir = os.path.join(self.downloaded_dir, dirname)
                    break

            if not comic_dir or not os.path.exists(comic_dir):
                return chapters

            # 检查是否有子目录（章节）
            subdirs = [
                d
                for d in os.listdir(comic_dir)
                if os.path.isdir(os.path.join(comic_dir, d))
            ]

            # 支持的图片扩展名
            image_extensions = {".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp"}

            if subdirs:
                # 尝试从JM网站获取章节顺序
                chapter_order = self._get_chapter_order_from_jm(jm_id)

                if chapter_order:
                    # 使用从JM获取的章节顺序
                    ordered_subdirs = []
                    for chapter_id in chapter_order:
                        if chapter_id in subdirs:
                            ordered_subdirs.append(chapter_id)
                    # 添加任何不在顺序中的章节（例如新下载的章节）
                    for subdir in subdirs:
                        if subdir not in ordered_subdirs:
                            ordered_subdirs.append(subdir)
                else:
                    # 如果无法从JM获取，使用数字排序作为后备
                    def sort_key(dirname):
                        try:
                            return int(dirname)
                        except ValueError:
                            return dirname

                    ordered_subdirs = sorted(subdirs, key=sort_key)

                # 多章节漫画
                for i, subdir in enumerate(ordered_subdirs):
                    subdir_path = os.path.join(comic_dir, subdir)

                    # 计算该章节的页数
                    page_count = 0
                    for filename in os.listdir(subdir_path):
                        file_ext = os.path.splitext(filename)[1].lower()
                        if file_ext in image_extensions:
                            page_count += 1

                    chapters.append(
                        {
                            "id": subdir,
                            "name": f"第{i + 1}章",
                            "pages": page_count,
                            "path": subdir_path,
                            "index": i,
                        }
                    )
            else:
                # 单章节漫画
                page_count = 0
                for filename in os.listdir(comic_dir):
                    file_ext = os.path.splitext(filename)[1].lower()
                    if file_ext in image_extensions and not filename.startswith(
                        "cover"
                    ):
                        page_count += 1

                if page_count > 0:
                    chapters.append(
                        {
                            "id": "1",
                            "name": "第1章",
                            "pages": page_count,
                            "path": comic_dir,
                            "index": 0,
                        }
                    )

            return chapters

        except Exception as e:
            print(f"获取漫画章节失败 {jm_id}: {e}")
            return chapters

    def get_comic_page_path(
        self, jm_id: int, page_num: int, chapter_id: Optional[str] = None
    ) -> Optional[str]:
        """获取漫画页面路径（支持章节）"""
        # 查找漫画目录
        comic_dir = None
        for dirname in os.listdir(self.downloaded_dir):
            if dirname.startswith(f"{jm_id}_"):
                comic_dir = os.path.join(self.downloaded_dir, dirname)
                break

        if not comic_dir:
            return None

        # 如果指定了章节，进入章节目录
        if chapter_id:
            chapter_path = os.path.join(comic_dir, chapter_id)
            if os.path.exists(chapter_path) and os.path.isdir(chapter_path):
                comic_dir = chapter_path
        else:
            # 先检查是否有以jm_id命名的子目录（向后兼容）
            subdir_path = os.path.join(comic_dir, str(jm_id))
            if os.path.exists(subdir_path) and os.path.isdir(subdir_path):
                comic_dir = subdir_path

        # 支持的图片命名格式
        possible_filenames = [
            f"{page_num:05d}.jpg",  # 00001.jpg
            f"{page_num:05d}.png",  # 00001.png
            f"{page_num:03d}.jpg",  # 001.jpg
            f"{page_num:03d}.png",  # 001.png
        ]

        for filename in possible_filenames:
            page_path = os.path.join(comic_dir, filename)
            if os.path.exists(page_path):
                return page_path

        return None

    def delete_comic(self, jm_id: int) -> bool:
        """删除漫画"""
        import sqlite3

        try:
            # 从数据库删除
            conn = sqlite3.connect(self.db_file)
            cursor = conn.cursor()

            cursor.execute("DELETE FROM downloaded_comics WHERE jm_id = ?", (jm_id,))
            conn.commit()
            conn.close()

            # 删除文件
            for dirname in os.listdir(self.downloaded_dir):
                if dirname.startswith(f"{jm_id}_"):
                    comic_dir = os.path.join(self.downloaded_dir, dirname)
                    if os.path.exists(comic_dir):
                        shutil.rmtree(comic_dir)
                    break

            return True

        except Exception as e:
            print(f"删除漫画失败 {jm_id}: {e}")
            return False

    def update_read_progress(self, jm_id: int, page_num: int):
        """更新阅读进度"""
        import sqlite3

        conn = sqlite3.connect(self.db_file)
        cursor = conn.cursor()

        try:
            cursor.execute(
                """
                UPDATE downloaded_comics 
                SET last_read_time = CURRENT_TIMESTAMP, read_progress = ?
                WHERE jm_id = ?
            """,
                (page_num, jm_id),
            )

            conn.commit()
        except Exception as e:
            print(f"更新阅读进度失败 {jm_id}: {e}")
        finally:
            conn.close()

    def get_cache_size(self) -> int:
        """获取缓存大小"""
        total_size = 0
        try:
            for dirpath, dirnames, filenames in os.walk(self.downloaded_dir):
                for filename in filenames:
                    filepath = os.path.join(dirpath, filename)
                    if os.path.exists(filepath):
                        total_size += os.path.getsize(filepath)
        except:
            pass
        return total_size
