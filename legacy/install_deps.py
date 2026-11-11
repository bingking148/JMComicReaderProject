#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
跨平台依赖安装脚本
自动检测操作系统并安装所需依赖
"""

import sys
import os
import subprocess
import platform
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent
REQUIREMENTS_FILE = PROJECT_ROOT / "requirements.txt"

DEPENDENCIES = [
    "flask>=3.0.0",
    "flask-cors>=4.0.0",
    "jmcomic>=1.0.0",
    "requests>=2.31.0",
    "pillow>=10.0.0",
    "img2pdf>=0.4.4",
    "aiofiles>=23.0.0",
    "aiohttp>=3.9.0",
    "pywebview>=5.0",
]

MIRROR_URLS = [
    "https://pypi.tuna.tsinghua.edu.cn/simple",
    "https://pypi.douban.com/simple",
    "https://mirrors.aliyun.com/pypi/simple/",
]


def print_header(message):
    width = 60
    border = "=" * width
    print(f"\n{border}")
    print(f"{message:^{width}}")
    print(f"{border}\n")


def run_command(command, capture_output=False):
    """执行命令"""
    try:
        if capture_output:
            result = subprocess.run(
                command,
                shell=True,
                capture_output=True,
                text=True,
                check=True
            )
            return result.stdout, result.returncode
        else:
            subprocess.run(command, shell=True, check=True)
            return "", 0
    except subprocess.CalledProcessError as e:
        return e.stderr, e.returncode


def check_python_version():
    """检查Python版本"""
    print("✓ 检查 Python 版本...")
    
    version = sys.version_info
    version_str = f"{version.major}.{version.minor}.{version.micro}"
    print(f"  当前版本: Python {version_str}")
    
    if version.major < 3 or (version.major == 3 and version.minor < 8):
        print(f"  ✗ Python 版本过低，需要 3.8 或更高版本")
        return False
    
    print(f"  ✓ Python 版本符合要求")
    return True


def check_pip():
    """检查pip是否可用"""
    print("✓ 检查 pip...")
    
    try:
        output, code = run_command(f"{sys.executable} -m pip --version", capture_output=True)
        if code == 0:
            print(f"  {output.strip()}")
            return True
    except:
        pass
    
    print("  ✗ pip 未安装或不可用")
    return False


def upgrade_pip():
    """升级pip"""
    print("✓ 升级 pip...")
    try:
        run_command(f"{sys.executable} -m pip install --upgrade pip -i {MIRROR_URLS[0]}")
        print("  ✓ pip 升级完成")
        return True
    except:
        print("  ✗ pip 升级失败，继续使用当前版本")
        return False


def install_dependencies():
    """安装依赖包"""
    print_header("📦 安装依赖包")
    
    requirements_content = "\n".join(DEPENDENCIES)
    
    if REQUIREMENTS_FILE.exists():
        print(f"  使用已有的 {REQUIREMENTS_FILE.name}")
        cmd = f'"{sys.executable}" -m pip install -r "{REQUIREMENTS_FILE}" -i {MIRROR_URLS[0]}'
    else:
        print(f"  {REQUIREMENTS_FILE.name} 不存在，使用内置依赖列表")
        print(f"  安装的依赖:")
        for dep in DEPENDENCIES:
            print(f"    - {dep}")
        
        temp_file = PROJECT_ROOT / "temp_requirements.txt"
        with open(temp_file, "w", encoding="utf-8") as f:
            f.write(requirements_content)
        cmd = f'"{sys.executable}" -m pip install -r "{temp_file}" -i {MIRROR_URLS[0]}'
    
    print("\n  正在安装...")
    
    for mirror in MIRROR_URLS:
        print(f"\n  尝试使用镜像源: {mirror}")
        cmd = cmd.replace(MIRROR_URLS[0], mirror)
        
        try:
            result = subprocess.run(cmd, shell=True, check=True)
            print("\n  ✓ 依赖安装成功！")
            if REQUIREMENTS_FILE.exists() == False and 'temp_file' in locals():
                temp_file.unlink(missing_ok=True)
            return True
        except subprocess.CalledProcessError:
            print(f"  ✗ 镜像源 {mirror} 安装失败，尝试下一个...")
            continue
    
    print("\n  ❌ 所有镜像源安装失败")
    print("  提示: 您可以手动运行以下命令:")
    print(f'  pip install {" ".join(DEPENDENCIES)}')
    return False


def verify_installation():
    """验证安装"""
    print_header("🔍 验证安装")
    
    all_installed = True
    modules = {
        "flask": "Flask",
        "flask_cors": "Flask-CORS",
        "jmcomic": "JMComic",
        "requests": "Requests",
        "PIL": "Pillow",
        "img2pdf": "img2pdf",
        "aiofiles": "aiofiles",
        "aiohttp": "aiohttp",
        "webview": "pywebview",
    }
    
    for module, name in modules.items():
        try:
            __import__(module)
            print(f"  ✓ {name} 已安装")
        except ImportError:
            print(f"  ✗ {name} 未安装")
            all_installed = False
    
    return all_installed


def create_startup_info():
    """创建启动信息文件"""
    info_file = PROJECT_ROOT / "install_info.txt"
    
    with open(info_file, "w", encoding="utf-8") as f:
        f.write(f"JM漫画阅读器 依赖安装信息\n")
        f.write(f"{'='*50}\n\n")
        f.write(f"安装时间: {subprocess.check_output(['date', '+%Y-%m-%d %H:%M:%S'], text=True).strip()}\n")
        f.write(f"操作系统: {platform.system()} {platform.release()}\n")
        f.write(f"Python版本: {sys.version}\n")
        f.write(f"Python路径: {sys.executable}\n\n")
        f.write(f"已安装依赖:\n")
        
        for dep in DEPENDENCIES:
            try:
                result = subprocess.run(
                    [sys.executable, "-m", "pip", "show", dep.split(">=")[0].split("==")[0]],
                    capture_output=True,
                    text=True,
                    check=True
                )
                version = None
                for line in result.stdout.split('\n'):
                    if line.startswith('Version:'):
                        version = line.split(':')[1].strip()
                        break
                if version:
                    f.write(f"  ✓ {dep}: {version}\n")
            except:
                f.write(f"  ✗ {dep}: 安装失败\n")
    
    print(f"\n✓ 安装信息已保存到 {info_file.name}")


def main():
    """主函数"""
    print_header("JM漫画阅读器 依赖安装程序")
    
    print(f"操作系统: {platform.system()} {platform.release()}")
    print(f"架构: {platform.machine()}\n")
    
    if not check_python_version():
        print("\n❌ Python 版本不符合要求")
        print("\n请安装 Python 3.8 或更高版本:")
        print("  Windows: https://www.python.org/downloads/")
        print("  macOS: brew install python3")
        print("  Linux: sudo apt-get install python3 python3-pip")
        input("\n按回车键退出...")
        sys.exit(1)
    
    if not check_pip():
        print("\n❌ pip 未安装或不可用")
        print("\n请先安装 pip:")
        print("  Windows: python -m ensurepip")
        print("  macOS/Linux: python3 -m ensurepip")
        input("\n按回车键退出...")
        sys.exit(1)
    
    upgrade_pip()
    
    if not install_dependencies():
        print("\n❌ 依赖安装失败")
        input("\n按回车键退出...")
        sys.exit(1)
    
    if verify_installation():
        create_startup_info()
        
        print_header("✅ 安装完成")
        print("\n所有依赖已成功安装！")
        print("\n现在您可以:")
        print("  Windows: 双击 '启动.bat' 文件")
        print("  macOS/Linux: 运行 'chmod +x 启动.sh && ./启动.sh'")
        print("\n或直接运行: python start.py")
    else:
        print("\n⚠ 部分依赖安装失败，可能影响功能")
    
    input("\n按回车键退出...")


if __name__ == "__main__":
    main()
