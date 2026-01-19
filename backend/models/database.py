# -*- coding: utf-8 -*-
"""
数据库模型和初始化
"""

import sqlite3
import os
from datetime import datetime
from typing import Optional


def init_database():
    """初始化数据库"""
    db_file = "E:\\JMComicReaderProject\\backend\\comics.db"

    # 确保目录存在
    os.makedirs(os.path.dirname(db_file), exist_ok=True)

    conn = sqlite3.connect(db_file)
    cursor = conn.cursor()

    # 创建搜索历史表
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS search_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            search_type TEXT NOT NULL,  -- 'jm_id' or 'keyword'
            search_content TEXT NOT NULL,
            results_count INTEGER DEFAULT 0,
            search_time DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 创建下载历史表
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS download_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jm_id INTEGER NOT NULL,
            title TEXT NOT NULL,
            download_status TEXT NOT NULL,  -- 'pending', 'downloading', 'completed', 'failed'
            download_time DATETIME DEFAULT CURRENT_TIMESTAMP,
            complete_time DATETIME,
            error_message TEXT
        )
    """)

    # 创建阅读历史表
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS reading_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            jm_id INTEGER NOT NULL,
            page_number INTEGER NOT NULL,
            read_time DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 创建系统配置表
    cursor.execute("""
        CREATE TABLE IF NOT EXISTS system_config (
            key TEXT PRIMARY KEY,
            value TEXT,
            description TEXT,
            update_time DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)

    # 插入默认配置
    default_configs = [
        ("download_path", "E:\\JMComicReaderProject\\DownloadedComics", "下载路径"),
        ("cache_path", "E:\\JMComicReaderProject\\TempCache", "缓存路径"),
        ("max_concurrent_downloads", "3", "最大并发下载数"),
        ("auto_cleanup_cache", "false", "自动清理缓存"),
        ("cache_size_limit", "104857600", "缓存大小限制(字节)"),
        ("image_quality", "85", "图片质量"),
        ("enable_pdf_generation", "true", "启用PDF生成"),
        ("theme", "light", "界面主题"),
    ]

    for key, value, desc in default_configs:
        cursor.execute(
            """
            INSERT OR IGNORE INTO system_config (key, value, description)
            VALUES (?, ?, ?)
        """,
            (key, value, desc),
        )

    conn.commit()
    conn.close()


def get_db_connection():
    """获取数据库连接"""
    db_file = "E:\\JMComicReaderProject\\backend\\comics.db"
    return sqlite3.connect(db_file, check_same_thread=False)


def add_search_history(search_type: str, search_content: str, results_count: int = 0):
    """添加搜索历史"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute(
            """
            INSERT INTO search_history (search_type, search_content, results_count)
            VALUES (?, ?, ?)
        """,
            (search_type, search_content, results_count),
        )

        conn.commit()
    except Exception as e:
        print(f"添加搜索历史失败: {e}")
    finally:
        conn.close()


def add_download_history(
    jm_id: int, title: str, status: str, error_message: Optional[str] = None
):
    """添加下载历史"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        if status == "completed":
            cursor.execute(
                """
                INSERT INTO download_history (jm_id, title, download_status, complete_time)
                VALUES (?, ?, ?, CURRENT_TIMESTAMP)
            """,
                (jm_id, title, status),
            )
        else:
            cursor.execute(
                """
                INSERT INTO download_history (jm_id, title, download_status, error_message)
                VALUES (?, ?, ?, ?)
            """,
                (jm_id, title, status, error_message),
            )

        conn.commit()
    except Exception as e:
        print(f"添加下载历史失败: {e}")
    finally:
        conn.close()


def add_reading_history(jm_id: int, page_number: int):
    """添加阅读历史"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute(
            """
            INSERT INTO reading_history (jm_id, page_number)
            VALUES (?, ?)
        """,
            (jm_id, page_number),
        )

        conn.commit()
    except Exception as e:
        print(f"添加阅读历史失败: {e}")
    finally:
        conn.close()


def get_system_config(key: str) -> Optional[str]:
    """获取系统配置"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT value FROM system_config WHERE key = ?", (key,))
        result = cursor.fetchone()
        return result[0] if result else None
    except Exception as e:
        print(f"获取系统配置失败: {e}")
        return None
    finally:
        conn.close()


def set_system_config(key: str, value: str):
    """设置系统配置"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        cursor.execute(
            """
            INSERT OR REPLACE INTO system_config (key, value, update_time)
            VALUES (?, ?, CURRENT_TIMESTAMP)
        """,
            (key, value),
        )

        conn.commit()
    except Exception as e:
        print(f"设置系统配置失败: {e}")
    finally:
        conn.close()


def cleanup_old_records(days: int = 30):
    """清理旧记录"""
    conn = get_db_connection()
    cursor = conn.cursor()

    try:
        # 清理30天前的搜索历史
        cursor.execute(
            """
            DELETE FROM search_history 
            WHERE search_time < datetime('now', '-' || ? || ' days')
        """,
            (days,),
        )

        # 清理30天前的阅读历史
        cursor.execute(
            """
            DELETE FROM reading_history 
            WHERE read_time < datetime('now', '-' || ? || ' days')
        """,
            (days,),
        )

        conn.commit()
    except Exception as e:
        print(f"清理旧记录失败: {e}")
    finally:
        conn.close()
