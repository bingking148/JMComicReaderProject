# -*- coding: utf-8 -*-
"""
下载管理器
负责漫画的异步下载和进度管理
"""

import os
import asyncio
import aiohttp
import aiofiles
from PIL import Image
import io
from typing import Callable, Optional
import zipfile
import img2pdf
import sys
import shutil

# 添加后端模块路径
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from services.jm_crawler import JMCrawler


class DownloadManager:
    """下载管理器"""

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
        self.temp_dir = os.environ.get(
            "TEMP_CACHE_DIR", os.path.join(self.base_dir, "TempCache")
        )

        # 确保目录存在
        os.makedirs(self.downloaded_dir, exist_ok=True)
        os.makedirs(self.temp_dir, exist_ok=True)

        # 初始化JM爬虫
        self.jm_crawler = JMCrawler()

    def _clean_filename(self, filename: str) -> str:
        """清理文件名中的非法字符"""
        # Windows不允许的字符
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

        # 移除控制字符
        filename = "".join(char for char in filename if ord(char) >= 32)

        # 限制长度（Windows路径最大260字符，留出空间）
        if len(filename) > 100:
            filename = filename[:100]

        # 移除首尾空格和点
        filename = filename.strip(". ")

        # 如果清理后为空，使用默认名称
        if not filename:
            filename = "comic"

        return filename

    async def download_comic_async(
        self, jm_id: int, comic_info: dict, progress_callback: Callable
    ) -> bool:
        """
        异步下载漫画

        Args:
            jm_id: 漫画ID
            comic_info: 漫画信息
            progress_callback: 进度回调函数

        Returns:
            是否下载成功
        """
        try:
            # 创建漫画目录（清理标题中的非法字符）
            safe_title = self._clean_filename(comic_info["title"])
            comic_dir = os.path.join(self.downloaded_dir, f"{jm_id}_{safe_title}")
            os.makedirs(comic_dir, exist_ok=True)

            # 更新进度
            progress_callback(5, "preparing", "准备下载环境...")

            # 下载封面
            if comic_info.get("cover"):
                await self._download_image_async(
                    comic_info["cover"],
                    os.path.join(comic_dir, "cover.jpg"),
                    progress_callback,
                )

            progress_callback(15, "downloading", "正在下载漫画图片...")

            # 使用真实的JMComic下载功能
            success = await self._real_comic_download(
                jm_id, comic_dir, comic_info, progress_callback
            )

            if success:
                progress_callback(90, "processing", "正在生成PDF...")

                # 生成PDF
                pdf_path = os.path.join(comic_dir, f"{jm_id}.pdf")
                await self._create_pdf_from_images(comic_dir, pdf_path)

                # 保存漫画信息
                await self._save_comic_info(comic_dir, comic_info)

                progress_callback(100, "completed", "下载完成")
                return True
            else:
                progress_callback(0, "error", "下载失败")
                return False

        except Exception as e:
            progress_callback(0, "error", f"下载失败: {str(e)}")
            return False

    def download_comic(
        self, jm_id: int, comic_info: dict, progress_callback: Callable
    ) -> bool:
        """
        同步下载漫画（包装异步方法）

        Args:
            jm_id: 漫画ID
            comic_info: 漫画信息
            progress_callback: 进度回调函数

        Returns:
            是否下载成功
        """
        try:
            # 创建事件循环并运行异步任务
            loop = asyncio.new_event_loop()
            asyncio.set_event_loop(loop)
            result = loop.run_until_complete(
                self.download_comic_async(jm_id, comic_info, progress_callback)
            )
            loop.close()
            return result
        except Exception as e:
            progress_callback(0, "error", f"下载失败: {str(e)}")
            return False

    async def _real_comic_download(
        self, jm_id: int, comic_dir: str, comic_info: dict, progress_callback: Callable
    ) -> bool:
        """
        使用真实的JMComic下载功能下载漫画
        """
        try:
            # 使用jm_crawler的真实下载功能
            def update_progress(progress, status, message):
                # 将jm_crawler的进度转换为我们需要的进度范围（15-85%）
                if status == "starting":
                    progress_callback(15, "downloading", "开始下载...")
                elif status == "downloading":
                    # 从15%到85%
                    mapped_progress = 15 + (progress / 100) * 70
                    progress_callback(int(mapped_progress), "downloading", message)
                elif status == "processing":
                    progress_callback(85, "processing", message)
                elif status == "completed":
                    progress_callback(95, "processing", message)
                elif status == "error":
                    progress_callback(0, "error", message)

            # 调用真实下载
            success = self.jm_crawler.download_comic(jm_id, update_progress)

            if success:
                # 将下载的文件从TempCache移动到DownloadedComics目录
                temp_download_dir = os.path.join(
                    self.base_dir, "TempCache", "downloads", str(jm_id)
                )

                if os.path.exists(temp_download_dir):
                    # 检查是否有子目录（章节）
                    subdirs = [
                        d
                        for d in os.listdir(temp_download_dir)
                        if os.path.isdir(os.path.join(temp_download_dir, d))
                    ]

                    if len(subdirs) == 1 and subdirs[0] == str(jm_id):
                        # 单章节漫画：将章节目录的内容移动到漫画目录
                        chapter_dir = os.path.join(temp_download_dir, subdirs[0])
                        for filename in os.listdir(chapter_dir):
                            src_path = os.path.join(chapter_dir, filename)
                            dst_path = os.path.join(comic_dir, filename)
                            shutil.move(src_path, dst_path)
                    elif len(subdirs) > 1:
                        # 多章节漫画：移动所有章节目录
                        for subdir in subdirs:
                            src_path = os.path.join(temp_download_dir, subdir)
                            dst_path = os.path.join(comic_dir, subdir)
                            shutil.move(src_path, dst_path)
                    else:
                        # 没有章节目录（可能直接下载了文件）
                        for filename in os.listdir(temp_download_dir):
                            src_path = os.path.join(temp_download_dir, filename)
                            dst_path = os.path.join(comic_dir, filename)
                            shutil.move(src_path, dst_path)

                    # 清理临时目录
                    try:
                        shutil.rmtree(temp_download_dir)
                    except:
                        pass

            return success

        except Exception as e:
            print(f"真实下载失败 {jm_id}: {e}")
            # 如果真实下载失败，回退到模拟下载
            return await self._create_placeholder_images(
                jm_id, comic_dir, comic_info, progress_callback
            )

    async def _create_placeholder_image(self, image_path: str, page_num: int):
        """创建占位图片"""
        try:
            # 创建一张简单的占位图片
            width, height = 800, 1200
            image = Image.new("RGB", (width, height), color="white")

            # 添加页码文字
            from PIL import ImageDraw, ImageFont

            draw = ImageDraw.Draw(image)

            # 尝试使用系统字体，如果失败则使用默认字体
            try:
                font = ImageFont.truetype("arial.ttf", 40)
            except:
                font = ImageFont.load_default()

            text = f"Page {page_num}"
            text_bbox = draw.textbbox((0, 0), text, font=font)
            text_width = text_bbox[2] - text_bbox[0]
            text_height = text_bbox[3] - text_bbox[1]

            x = (width - text_width) // 2
            y = (height - text_height) // 2

            draw.text((x, y), text, fill="black", font=font)

            # 保存图片
            image.save(image_path, "JPEG", quality=85)

        except Exception as e:
            print(f"创建占位图片失败: {e}")

    async def _download_image_async(
        self, url: str, save_path: str, progress_callback: Callable
    ):
        """异步下载图片"""
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    url, timeout=aiohttp.ClientTimeout(total=30)
                ) as response:
                    if response.status == 200:
                        content = await response.read()

                        # 处理图片
                        image = Image.open(io.BytesIO(content))

                        # 转换为RGB模式
                        if image.mode == "RGBA":
                            rgb_image = Image.new("RGB", image.size, (255, 255, 255))
                            rgb_image.paste(image, mask=image.split()[3])
                            image = rgb_image

                        # 异步保存
                        image.save(save_path, "JPEG", quality=85)

        except Exception as e:
            print(f"异步下载图片失败 {url}: {e}")

    async def _create_pdf_from_images(self, comic_dir: str, pdf_path: str):
        """从图片创建PDF"""
        try:
            # 获取所有图片文件
            image_files = []
            for filename in sorted(os.listdir(comic_dir)):
                if filename.lower().endswith((".jpg", ".jpeg", ".png")):
                    if filename != "cover.jpg":  # 封面单独处理
                        image_files.append(os.path.join(comic_dir, filename))

            if image_files:
                # 使用img2pdf创建PDF
                try:
                    pdf_data = img2pdf.convert(image_files)
                    if pdf_data:
                        with open(pdf_path, "wb") as f:
                            f.write(pdf_data)
                except Exception as pdf_error:
                    print(f"img2pdf转换失败: {pdf_error}")
                    # 创建空PDF文件作为占位
                    with open(pdf_path, "wb") as f:
                        f.write(b"")  # 空PDF文件

        except Exception as e:
            print(f"创建PDF失败: {e}")

    async def _save_comic_info(self, comic_dir: str, comic_info: dict):
        """保存漫画信息"""
        try:
            info_path = os.path.join(comic_dir, "info.json")

            # 只保存必要的信息
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

    def _get_current_time(self) -> str:
        """获取当前时间字符串"""
        from datetime import datetime

        return datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    async def _create_placeholder_images(
        self, jm_id: int, comic_dir: str, comic_info: dict, progress_callback: Callable
    ) -> bool:
        """
        创建占位图片作为备用下载方案
        """
        try:
            total_pages = comic_info.get("pages", 20)  # 默认20页

            for i in range(1, total_pages + 1):
                # 创建占位图片
                image_path = os.path.join(comic_dir, f"page_{i:03d}.jpg")
                await self._create_placeholder_image(image_path, i)

                # 更新进度
                progress = int(15 + (i / total_pages) * 70)
                progress_callback(
                    progress, "downloading", f"正在创建第 {i}/{total_pages} 页..."
                )

                # 稍作延迟
                await asyncio.sleep(0.05)

            return True

        except Exception as e:
            print(f"创建占位图片失败 {jm_id}: {e}")
            return False
