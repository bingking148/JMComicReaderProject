# -*- coding: utf-8 -*-
"""
下载管理器。
"""

import asyncio
import io
import os
import shutil
import sys
from datetime import datetime
from typing import Callable

import aiohttp
import img2pdf
from PIL import Image

# 添加后端模块路径
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from backend.services.jm_crawler import JMCrawler
except ImportError:
    try:
        from services.jm_crawler import JMCrawler
    except ImportError:
        sys.path.append(
            os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        )
        from backend.services.jm_crawler import JMCrawler


class DownloadManager:
    """负责漫画的异步下载和落库。"""

    def __init__(self):
        self.base_dir = os.environ.get(
            "BASE_DIR",
            os.path.dirname(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            ),
        )
        self.downloaded_dir = os.environ.get(
            "DOWNLOAD_DIR", os.path.join(self.base_dir, "DownloadedComics")
        )
        self.temp_dir = os.environ.get(
            "TEMP_CACHE_DIR", os.path.join(self.base_dir, "TempCache")
        )

        os.makedirs(self.downloaded_dir, exist_ok=True)
        os.makedirs(self.temp_dir, exist_ok=True)

        self.jm_crawler = JMCrawler()

    def _clean_filename(self, filename: str) -> str:
        illegal_chars = [
            "<",
            ">",
            ":",
            '"',
            "|",
            "?",
            "*",
            "\\",
            "/",
            "[",
            "]",
            "(",
            ")",
        ]
        for char in illegal_chars:
            filename = filename.replace(char, "_")

        filename = "".join(char for char in filename if ord(char) >= 32)
        if len(filename) > 100:
            filename = filename[:100]
        filename = filename.strip(". ")

        return filename or "comic"

    def _get_current_time(self) -> str:
        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def download_comic(
        self, jm_id: int, comic_info: dict, progress_callback: Callable
    ) -> bool:
        """同步包装异步下载。"""
        loop = asyncio.new_event_loop()
        try:
            asyncio.set_event_loop(loop)
            return loop.run_until_complete(
                self.download_comic_async(jm_id, comic_info, progress_callback)
            )
        except Exception as e:
            progress_callback(0, "error", f"下载失败: {str(e)}")
            return False
        finally:
            loop.close()

    async def download_comic_async(
        self, jm_id: int, comic_info: dict, progress_callback: Callable
    ) -> bool:
        """异步下载漫画。"""
        try:
            safe_title = self._clean_filename(comic_info["title"])
            comic_dir = os.path.join(self.downloaded_dir, f"{jm_id}_{safe_title}")
            os.makedirs(comic_dir, exist_ok=True)

            progress_callback(5, "preparing", "准备下载环境...")

            if comic_info.get("cover"):
                await self._download_image_async(
                    comic_info["cover"],
                    os.path.join(comic_dir, "cover.jpg"),
                )

            progress_callback(15, "downloading", "正在下载漫画图片...")

            success = await self._real_comic_download(
                jm_id, comic_dir, progress_callback
            )
            if not success:
                raise RuntimeError("下载失败，未生成可用文件")

            progress_callback(90, "processing", "正在生成 PDF...")
            pdf_path = os.path.join(comic_dir, f"{jm_id}.pdf")
            await self._create_pdf_from_images(comic_dir, pdf_path)

            await self._save_comic_info(comic_dir, comic_info)
            await self._ensure_files_ready(comic_dir, jm_id)

            progress_callback(100, "completed", "下载完成")
            return True

        except Exception as e:
            progress_callback(0, "error", f"下载失败: {str(e)}")
            return False

    async def _real_comic_download(
        self, jm_id: int, comic_dir: str, progress_callback: Callable
    ) -> bool:
        """执行真实下载流程，失败时直接报错，不再生成占位内容。"""

        def update_progress(progress, status, message):
            if status == "starting":
                progress_callback(15, "downloading", "开始下载...")
            elif status == "downloading":
                mapped_progress = 15 + (progress / 100) * 70
                progress_callback(int(mapped_progress), "downloading", message)
            elif status == "processing":
                progress_callback(85, "processing", message)
            elif status == "completed":
                progress_callback(95, "processing", message)
            elif status == "error":
                progress_callback(0, "error", message)

        try:
            success = self.jm_crawler.download_comic(jm_id, update_progress)
            if not success:
                return False

            temp_download_dir = os.path.join(
                self.base_dir, "TempCache", "downloads", str(jm_id)
            )
            if not os.path.exists(temp_download_dir):
                return False

            subdirs = [
                name
                for name in os.listdir(temp_download_dir)
                if os.path.isdir(os.path.join(temp_download_dir, name))
            ]

            if len(subdirs) == 1 and subdirs[0] == str(jm_id):
                chapter_dir = os.path.join(temp_download_dir, subdirs[0])
                for filename in os.listdir(chapter_dir):
                    shutil.move(
                        os.path.join(chapter_dir, filename),
                        os.path.join(comic_dir, filename),
                    )
            elif len(subdirs) > 1:
                for subdir in subdirs:
                    shutil.move(
                        os.path.join(temp_download_dir, subdir),
                        os.path.join(comic_dir, subdir),
                    )
            else:
                for filename in os.listdir(temp_download_dir):
                    shutil.move(
                        os.path.join(temp_download_dir, filename),
                        os.path.join(comic_dir, filename),
                    )

            try:
                shutil.rmtree(temp_download_dir)
            except Exception:
                pass

            return True

        except Exception as e:
            print(f"真实下载失败 {jm_id}: {e}")
            raise RuntimeError(f"真实下载失败: {e}") from e

    async def _download_image_async(self, url: str, save_path: str):
        """异步下载图片。"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    url, timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status != 200:
                        return

                    content = await response.read()
                    image = Image.open(io.BytesIO(content))
                    if image.mode == "RGBA":
                        rgb_image = Image.new("RGB", image.size, (255, 255, 255))
                        rgb_image.paste(image, mask=image.split()[3])
                        image = rgb_image

                    image.save(save_path, "JPEG", quality=85)
        except Exception as e:
            print(f"异步下载图片失败 {url}: {e}")

    async def _create_pdf_from_images(self, comic_dir: str, pdf_path: str):
        """从根目录图片创建 PDF。章节目录仍以图片阅读为主。"""
        try:
            image_files = []
            for filename in sorted(os.listdir(comic_dir)):
                if filename.lower().endswith((".jpg", ".jpeg", ".png")):
                    if filename != "cover.jpg":
                        image_files.append(os.path.join(comic_dir, filename))

            if not image_files:
                return

            try:
                pdf_data = img2pdf.convert(image_files)
                if pdf_data:
                    with open(pdf_path, "wb") as f:
                        f.write(pdf_data)
            except Exception as pdf_error:
                print(f"img2pdf 转换失败: {pdf_error}")
        except Exception as e:
            print(f"创建 PDF 失败: {e}")

    async def _save_comic_info(self, comic_dir: str, comic_info: dict):
        """保存漫画元信息。"""
        try:
            info_path = os.path.join(comic_dir, "info.json")
            save_info = {
                "id": comic_info.get("id"),
                "title": comic_info.get("title"),
                "author": comic_info.get("author"),
                "tags": comic_info.get("tags", []),
                "description": comic_info.get("description"),
                "favorites": comic_info.get("favorites", 0),
                "pages": comic_info.get("pages", 0),
                "download_time": self._get_current_time(),
            }

            import json

            with open(info_path, "w", encoding="utf-8") as f:
                json.dump(save_info, f, ensure_ascii=False, indent=2)
        except Exception as e:
            print(f"保存漫画信息失败: {e}")

    async def _ensure_files_ready(self, comic_dir: str, jm_id: int):
        """等待文件落盘后再写数据库。"""
        try:
            await asyncio.sleep(1)

            required_files = []
            subdirs = [
                name
                for name in os.listdir(comic_dir)
                if os.path.isdir(os.path.join(comic_dir, name))
            ]

            if subdirs:
                for subdir in subdirs:
                    chapter_path = os.path.join(comic_dir, subdir)
                    images = [
                        filename
                        for filename in os.listdir(chapter_path)
                        if filename.lower().endswith(
                            (".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp")
                        )
                    ]
                    required_files.extend(
                        os.path.join(chapter_path, filename) for filename in images
                    )
            else:
                images = [
                    filename
                    for filename in os.listdir(comic_dir)
                    if filename.lower().endswith(
                        (".jpg", ".jpeg", ".png", ".bmp", ".gif", ".webp")
                    )
                    and not filename.startswith("cover")
                ]
                required_files.extend(
                    os.path.join(comic_dir, filename) for filename in images
                )

            wait_time = 0
            while wait_time < 10:
                all_ready = True
                for file_path in required_files:
                    if not os.path.exists(file_path) or os.path.getsize(file_path) == 0:
                        all_ready = False
                        break

                if all_ready:
                    break

                await asyncio.sleep(1)
                wait_time += 1

            print(f"漫画 {jm_id} 文件准备就绪，共 {len(required_files)} 个文件")

            try:
                from services.comic_manager import ComicManager
            except ImportError:
                from backend.services.comic_manager import ComicManager

            comic_manager = ComicManager()
            info_path = os.path.join(comic_dir, "info.json")
            comic_info = {}
            if os.path.exists(info_path):
                import json

                with open(info_path, "r", encoding="utf-8") as f:
                    comic_info = json.load(f)

            comic_info["id"] = jm_id
            success = comic_manager.add_downloaded_comic(jm_id, comic_info)
            if success:
                print(f"漫画 {jm_id} 已添加到数据库")
            else:
                print(f"漫画 {jm_id} 添加到数据库失败")

        except Exception as e:
            print(f"确保文件准备就绪失败 {jm_id}: {e}")
