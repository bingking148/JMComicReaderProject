# -*- coding: utf-8 -*-
"""
JMComicReaderProject 后端主应用
"""

import os
import sys
from flask import Flask, render_template, jsonify, request, send_file
from flask_cors import CORS
import json
import sqlite3
from datetime import datetime
import asyncio
import threading

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMP_CACHE_DIR = os.environ.get(
    "TEMP_CACHE_DIR", os.path.join(PROJECT_ROOT, "TempCache")
)
DOWNLOAD_DIR = os.environ.get(
    "DOWNLOAD_DIR", os.path.join(PROJECT_ROOT, "DownloadedComics")
)
BASE_DIR = os.environ.get("BASE_DIR", PROJECT_ROOT)

# 添加后端模块路径
sys.path.append(os.path.dirname(os.path.abspath(__file__)))

from services.jm_crawler import JMCrawler
from services.download_manager import DownloadManager
from services.comic_manager import ComicManager
from models.database import init_database

app = Flask(
    __name__,
    template_folder="../frontend/templates",
    static_folder="../frontend/static",
)

CORS(app)

# 初始化服务
jm_crawler = JMCrawler()
download_manager = DownloadManager()
comic_manager = ComicManager()

# 全局变量存储下载进度
download_progress = {}


@app.route("/")
def index():
    """首页"""
    return render_template("index.html")


@app.route("/api/search/jm/<int:jm_id>")
def search_by_jm_id(jm_id):
    """通过JM号精准搜索"""
    try:
        comic_info = jm_crawler.get_comic_info(jm_id)
        if comic_info:
            return jsonify({"success": True, "data": comic_info})
        else:
            return jsonify({"success": False, "message": "未找到对应的漫画"})
    except Exception as e:
        return jsonify({"success": False, "message": f"搜索失败: {str(e)}"})


@app.route("/api/search/keyword")
def search_by_keyword():
    """关键词模糊搜索"""
    keyword = request.args.get("keyword", "").strip()
    sort_order = request.args.get("sort", "desc")  # desc or asc

    if not keyword:
        return jsonify({"success": False, "message": "关键词不能为空"})

    try:
        results = jm_crawler.search_by_keyword(keyword, sort_order)
        return jsonify({"success": True, "data": results})
    except Exception as e:
        return jsonify({"success": False, "message": f"搜索失败: {str(e)}"})


@app.route("/api/cover/<int:jm_id>")
def get_comic_cover(jm_id):
    """获取漫画封面（懒加载）"""
    try:
        # 首先检查是否已下载漫画的封面
        if comic_manager.is_comic_downloaded(jm_id):
            # 查找已下载漫画的封面
            downloaded_comics = comic_manager.get_downloaded_comics()
            for comic in downloaded_comics:
                if comic["id"] == jm_id and comic.get("cover_path"):
                    cover_path = comic["cover_path"]
                    if os.path.exists(cover_path):
                        print(f"返回已下载漫画封面: {cover_path}")
                        return send_file(cover_path)
        
        # 如果没有已下载封面，从JM获取
        cover_url = jm_crawler.get_cover_url(jm_id)
        if cover_url:
            return jsonify(
                {
                    "success": True,
                    "data": {
                        "cover": cover_url,
                        "cover_local": os.path.join(
                            TEMP_CACHE_DIR, f"cover_{jm_id}.jpg"
                        ),
                    },
                }
            )
        else:
            return jsonify({"success": False, "message": "未找到封面"})
    except Exception as e:
        return jsonify({"success": False, "message": f"获取封面失败: {str(e)}"})


@app.route("/api/cover/downloaded/<int:jm_id>")
def get_downloaded_comic_cover(jm_id):
    """获取已下载漫画的封面"""
    try:
        # 查找已下载漫画的封面
        downloaded_comics = comic_manager.get_downloaded_comics()
        for comic in downloaded_comics:
            if comic["id"] == jm_id and comic.get("cover_path"):
                cover_path = comic["cover_path"]
                if os.path.exists(cover_path):
                    print(f"返回已下载漫画封面: {cover_path}")
                    return send_file(cover_path)
        
        return jsonify({"success": False, "message": "封面不存在"})
    except Exception as e:
        return jsonify({"success": False, "message": f"获取封面失败: {str(e)}"})


@app.route("/api/download/<int:jm_id>", methods=["POST"])
def download_comic(jm_id):
    """下载漫画"""
    try:
        # 检查是否已下载
        if comic_manager.is_comic_downloaded(jm_id):
            return jsonify(
                {"success": False, "message": "该漫画已下载", "downloaded": True}
            )

        # 获取漫画信息
        comic_info = jm_crawler.get_comic_info(jm_id)
        if not comic_info:
            return jsonify({"success": False, "message": "未找到对应的漫画"})

        # 启动异步下载任务
        download_id = f"{jm_id}_{datetime.now().strftime('%Y%m%d%H%M%S')}"
        download_progress[download_id] = {
            "progress": 0,
            "status": "starting",
            "message": "开始下载...",
        }

        # 在新线程中执行下载
        def download_task():
            try:
                download_manager.download_comic(
                    jm_id,
                    comic_info,
                    lambda p, s, m: update_download_progress(download_id, p, s, m),
                )
                # 下载完成后添加到已下载列表
                # 注意：数据库更新已在download_manager中处理
                print(f"漫画 {jm_id} 下载任务完成")
            except Exception as e:
                update_download_progress(download_id, 0, "error", str(e))

        thread = threading.Thread(target=download_task)
        thread.daemon = True
        thread.start()

        return jsonify(
            {"success": True, "download_id": download_id, "message": "下载任务已启动"}
        )

    except Exception as e:
        return jsonify({"success": False, "message": f"下载失败: {str(e)}"})


def update_download_progress(download_id, progress, status, message):
    """更新下载进度"""
    if download_id in download_progress:
        download_progress[download_id].update(
            {"progress": progress, "status": status, "message": message}
        )


@app.route("/api/download/progress/<download_id>")
def get_download_progress(download_id):
    """获取下载进度"""
    if download_id in download_progress:
        return jsonify({"success": True, "data": download_progress[download_id]})
    else:
        return jsonify({"success": False, "message": "下载任务不存在"})


@app.route("/api/downloaded")
def get_downloaded_comics():
    """获取已下载的漫画列表"""
    try:
        comics = comic_manager.get_downloaded_comics()
        return jsonify({"success": True, "data": comics})
    except Exception as e:
        return jsonify({"success": False, "message": f"获取列表失败: {str(e)}"})


@app.route("/api/read/<int:jm_id>")
def read_comic(jm_id):
    """阅读漫画"""
    try:
        print(f"请求阅读漫画: {jm_id}")
        
        if not comic_manager.is_comic_downloaded(jm_id):
            print(f"漫画 {jm_id} 尚未下载")
            return jsonify({"success": False, "message": "该漫画尚未下载"})

        # 获取章节信息
        chapters = comic_manager.get_comic_chapters(jm_id)
        print(f"获取到 {len(chapters)} 个章节")
        
        if len(chapters) == 0:
            print(f"漫画 {jm_id} 没有可用的章节")
            return jsonify({"success": False, "message": "没有可用的章节"})

        # 默认返回第一章节信息
        first_chapter = chapters[0]
        print(f"使用第一章节: {first_chapter['id']}")
        
        # 获取漫画标题
        comic_title = f"JM-{jm_id}"
        try:
            downloaded_comics = comic_manager.get_downloaded_comics()
            for comic in downloaded_comics:
                if comic["id"] == jm_id:
                    comic_title = comic["title"]
                    break
        except Exception as e:
            print(f"获取漫画标题失败: {e}")
        
        result = {
            "success": True,
            "data": {
                "title": comic_title,
                "chapters": chapters,
                "current_chapter": first_chapter["id"],
                "current_chapter_pages": first_chapter["pages"],
                "total_chapters": len(chapters),
                "comic_path": first_chapter["path"],
            },
        }
        
        print(f"返回阅读数据: {result}")
        return result

    except Exception as e:
        print(f"获取阅读数据失败 {jm_id}: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"success": False, "message": f"获取阅读数据失败: {str(e)}"})


@app.route("/api/read/<int:jm_id>/chapter/<chapter_id>")
def read_comic_chapter(jm_id, chapter_id):
    """阅读指定章节"""
    try:
        print(f"请求阅读章节: {jm_id}-{chapter_id}")
        
        if not comic_manager.is_comic_downloaded(jm_id):
            print(f"漫画 {jm_id} 尚未下载")
            return jsonify({"success": False, "message": "该漫画尚未下载"})

        # 获取章节信息
        chapters = comic_manager.get_comic_chapters(jm_id)
        print(f"获取到 {len(chapters)} 个章节")
        
        target_chapter = None
        for chapter in chapters:
            if chapter["id"] == chapter_id:
                target_chapter = chapter
                break

        if not target_chapter:
            print(f"章节 {chapter_id} 不存在")
            return jsonify({"success": False, "message": "章节不存在"})

        # 获取漫画标题
        comic_title = f"JM-{jm_id}"
        try:
            downloaded_comics = comic_manager.get_downloaded_comics()
            for comic in downloaded_comics:
                if comic["id"] == jm_id:
                    comic_title = comic["title"]
                    break
        except Exception as e:
            print(f"获取漫画标题失败: {e}")

        result = {
            "success": True,
            "data": {
                "title": comic_title,
                "chapters": chapters,
                "current_chapter": target_chapter["id"],
                "current_chapter_pages": target_chapter["pages"],
                "total_chapters": len(chapters),
                "comic_path": target_chapter["path"],
            },
        }
        
        print(f"返回章节数据: {result}")
        return result

    except Exception as e:
        print(f"获取章节数据失败 {jm_id}-{chapter_id}: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"success": False, "message": f"获取章节数据失败: {str(e)}"})


@app.route("/api/comic/<int:jm_id>/page/<int:page_num>")
def get_comic_page(jm_id, page_num):
    """获取漫画页面"""
    try:
        # 获取章节参数
        chapter_id = request.args.get("chapter", None)
        print(f"请求漫画页面: {jm_id}-{page_num}, 章节: {chapter_id}")
        
        page_path = comic_manager.get_comic_page_path(jm_id, page_num, chapter_id)

        if page_path and os.path.exists(page_path):
            print(f"返回页面: {page_path}")
            return send_file(page_path)
        else:
            print(f"页面不存在: {page_path}")
            return jsonify({"success": False, "message": "页面不存在"})
    except Exception as e:
        print(f"获取页面失败 {jm_id}-{page_num}: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"success": False, "message": f"获取页面失败: {str(e)}"})


@app.route("/api/delete/<int:jm_id>", methods=["DELETE"])
def delete_comic(jm_id):
    """删除漫画"""
    try:
        if comic_manager.delete_comic(jm_id):
            return jsonify({"success": True, "message": "删除成功"})
        else:
            return jsonify({"success": False, "message": "删除失败"})
    except Exception as e:
        return jsonify({"success": False, "message": f"删除失败: {str(e)}"})


@app.route("/api/cache/status")
def get_cache_status():
    """获取缓存状态"""
    try:
        cache_size = get_directory_size(TEMP_CACHE_DIR)
        return jsonify(
            {
                "success": True,
                "data": {
                    "cache_size": cache_size,
                    "cache_size_mb": round(cache_size / (1024 * 1024), 2),
                    "need_cleanup": cache_size > 100 * 1024 * 1024,  # 100MB
                },
            }
        )
    except Exception as e:
        return jsonify({"success": False, "message": f"获取缓存状态失败: {str(e)}"})


@app.route("/api/cache/clear", methods=["POST"])
def clear_cache():
    """清理缓存"""
    try:
        cache_dir = TEMP_CACHE_DIR

        # 获取清理前的缓存大小
        original_size = get_directory_size(cache_dir)

        # 清理缓存目录（保留已下载漫画的封面和cover_cache.json）
        if os.path.exists(cache_dir):
            # 获取所有已下载漫画的封面路径
            downloaded_cover_paths = set()
            try:
                downloaded_comics = comic_manager.get_downloaded_comics()
                for comic in downloaded_comics:
                    if comic.get("cover_path") and os.path.exists(comic["cover_path"]):
                        # 获取封面文件名
                        cover_filename = os.path.basename(comic["cover_path"])
                        downloaded_cover_paths.add(cover_filename)
                        print(f"保护已下载漫画封面: {cover_filename}")
            except Exception as e:
                print(f"获取已下载漫画封面列表失败: {e}")

            # 保留的文件列表
            protected_files = {"cover_cache.json"}
            protected_files.update(downloaded_cover_paths)

            print(f"保护的文件: {protected_files}")

            # 清理缓存目录
            deleted_count = 0
            for item in os.listdir(cache_dir):
                item_path = os.path.join(cache_dir, item)
                
                # 跳过保护的文件
                if item in protected_files:
                    print(f"跳过保护文件: {item}")
                    continue

                try:
                    if os.path.isfile(item_path):
                        os.remove(item_path)
                        deleted_count += 1
                        print(f"删除文件: {item}")
                    elif os.path.isdir(item_path):
                        import shutil
                        shutil.rmtree(item_path)
                        print(f"删除目录: {item}")
                except Exception as e:
                    print(f"删除 {item_path} 失败: {e}")
                    continue

            print(f"缓存清理完成，共删除 {deleted_count} 个文件/目录")

        # 获取清理后的缓存大小
        final_size = get_directory_size(cache_dir)
        cleared_size = original_size - final_size

        return jsonify(
            {
                "success": True,
                "data": {
                    "cleared_size": cleared_size,
                    "cleared_size_mb": round(cleared_size / (1024 * 1024), 2),
                    "remaining_size": final_size,
                    "remaining_size_mb": round(final_size / (1024 * 1024), 2),
                    "message": f"成功清理了 {round(cleared_size / (1024 * 1024), 2)} MB 的缓存",
                },
            }
        )
    except Exception as e:
        print(f"清理缓存失败: {e}")
        import traceback
        traceback.print_exc()
        return jsonify({"success": False, "message": f"清理缓存失败: {str(e)}"})


def get_directory_size(directory):
    """获取目录大小"""
    total_size = 0
    try:
        for dirpath, dirnames, filenames in os.walk(directory):
            for filename in filenames:
                filepath = os.path.join(dirpath, filename)
                if os.path.exists(filepath):
                    total_size += os.path.getsize(filepath)
    except:
        pass
    return total_size


def clear_directory(directory):
    """清理目录"""
    try:
        if not os.path.exists(directory):
            return True

        # 删除目录下的所有文件和子目录
        for filename in os.listdir(directory):
            filepath = os.path.join(directory, filename)
            try:
                if os.path.isfile(filepath):
                    os.remove(filepath)
                elif os.path.isdir(filepath):
                    import shutil

                    shutil.rmtree(filepath)
            except Exception as e:
                print(f"删除 {filepath} 失败: {e}")
                continue
        return True
    except Exception as e:
        print(f"清理目录 {directory} 失败: {e}")
        return False


@app.route("/search")
def search_page():
    """搜索页面"""
    return render_template("search.html")


@app.route("/downloaded")
def downloaded_page():
    """已下载页面"""
    return render_template("downloaded.html")


@app.route("/detail/<int:jm_id>")
def detail_page(jm_id):
    """详情页面"""
    return render_template("detail.html", jm_id=jm_id)


@app.route("/reader/<int:jm_id>")
def reader_page(jm_id):
    """阅读页面"""
    return render_template("reader.html", jm_id=jm_id)


def main():
    """主函数"""
    # 初始化数据库
    init_database()

    # 启动应用
    app.run(debug=True, host="0.0.0.0", port=5000)


if __name__ == "__main__":
    main()
