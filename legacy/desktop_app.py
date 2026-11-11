#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
桌面版启动入口。

启动本地 Flask 服务并用原生桌面窗口承载页面，而不是交给外部浏览器。
同时把用户数据固定放到系统用户目录，避免更新程序时丢失下载内容。
"""

import os
import shutil
import socket
import sys
import threading
import time
import urllib.request
import webbrowser
from pathlib import Path

from werkzeug.serving import make_server


APP_NAME = "JMComicReader"
WINDOWS_APP_ID = "JMComicReader.Desktop"
WINDOW_TITLE = "JMComicReader"
WINDOW_WIDTH = 1360
WINDOW_HEIGHT = 900
WINDOW_MIN_SIZE = (980, 680)


def is_frozen():
    return getattr(sys, "frozen", False)


def get_exec_dir() -> Path:
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


def get_default_user_base_dir() -> Path:
    env_base_dir = os.environ.get("BASE_DIR")
    if env_base_dir:
        return Path(env_base_dir).expanduser().resolve()

    if not is_frozen():
        return get_exec_dir()

    if os.name == "nt":
        parent = (
            os.environ.get("LOCALAPPDATA")
            or os.environ.get("APPDATA")
            or str(get_exec_dir())
        )
        return Path(parent) / APP_NAME

    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME

    return Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share")) / APP_NAME


def _move_if_missing(source: Path, target: Path):
    if not source.exists():
        return

    if target.exists():
        if source.is_dir() and target.is_dir():
            try:
                if any(target.iterdir()):
                    return
            except OSError:
                return

            for child in source.iterdir():
                shutil.move(str(child), str(target / child.name))

            try:
                source.rmdir()
            except OSError:
                pass
        return

    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.move(str(source), str(target))


def migrate_legacy_data(base_dir: Path):
    """
    把旧版本放在 exe 同目录的数据迁移到用户目录。
    只在打包环境中执行，且目标不存在时才迁移，避免覆盖新数据。
    """
    if not is_frozen() or os.environ.get("BASE_DIR"):
        return

    legacy_base_dir = get_exec_dir()
    if legacy_base_dir == base_dir:
        return

    migrations = [
        (legacy_base_dir / "DownloadedComics", base_dir / "DownloadedComics"),
        (legacy_base_dir / "TempCache", base_dir / "TempCache"),
        (legacy_base_dir / "backend" / "comics.db", base_dir / "backend" / "comics.db"),
        (legacy_base_dir / "jm_option.yml", base_dir / "jm_option.yml"),
        (legacy_base_dir / "backend" / "jm_option.yml", base_dir / "backend" / "jm_option.yml"),
    ]

    for source, target in migrations:
        try:
            _move_if_missing(source, target)
        except Exception as exc:
            print(f"迁移数据失败: {source} -> {target}: {exc}")


def configure_runtime_env() -> Path:
    base_dir = get_default_user_base_dir()
    migrate_legacy_data(base_dir)

    download_dir = base_dir / "DownloadedComics"
    temp_cache_dir = base_dir / "TempCache"
    backend_dir = base_dir / "backend"

    download_dir.mkdir(parents=True, exist_ok=True)
    temp_cache_dir.mkdir(parents=True, exist_ok=True)
    backend_dir.mkdir(parents=True, exist_ok=True)

    os.environ["BASE_DIR"] = str(base_dir)
    os.environ["DOWNLOAD_DIR"] = str(download_dir)
    os.environ["TEMP_CACHE_DIR"] = str(temp_cache_dir)

    return base_dir


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def configure_windows_app_id():
    if os.name != "nt":
        return

    try:
        import ctypes

        ctypes.windll.shell32.SetCurrentProcessExplicitAppUserModelID(
            WINDOWS_APP_ID
        )
    except Exception:
        pass


def wait_for_server(url: str, timeout: float = 10.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=1):
                return
        except Exception:
            time.sleep(0.1)
    raise TimeoutError(f"服务启动超时: {url}")


class FlaskServerThread(threading.Thread):
    def __init__(self, app, host: str, port: int):
        super().__init__(daemon=True)
        self.host = host
        self.port = port
        self._server = make_server(host, port, app, threaded=True)

    def run(self):
        self._server.serve_forever()

    def shutdown(self):
        self._server.shutdown()


def run_desktop():
    configure_windows_app_id()
    base_dir = configure_runtime_env()

    from backend.app import app

    port = find_free_port()
    url = f"http://127.0.0.1:{port}"
    server = FlaskServerThread(app, "127.0.0.1", port)
    server.start()
    wait_for_server(url)

    try:
        import webview
    except ImportError:
        print("未安装 pywebview，回退到浏览器模式。")
        print(f"当前数据目录: {base_dir}")
        webbrowser.open(url)
        try:
            while True:
                time.sleep(1)
        except KeyboardInterrupt:
            pass
    else:
        window = webview.create_window(
            WINDOW_TITLE,
            url,
            width=WINDOW_WIDTH,
            height=WINDOW_HEIGHT,
            min_size=WINDOW_MIN_SIZE,
        )
        try:
            webview.start(debug=False)
        finally:
            try:
                window.destroy()
            except Exception:
                pass
    finally:
        server.shutdown()


if __name__ == "__main__":
    run_desktop()
