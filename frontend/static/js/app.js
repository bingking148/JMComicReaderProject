// 全局变量和工具函数
// 动态获取API基础URL
const API_BASE_URL = (() => {
    // 如果是开发环境，使用相对路径
    if (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1') {
        return '/api';
    } else {
        // 生产环境，使用当前主机的相对路径
        return '/api';
    }
})();

console.log('API_BASE_URL:', API_BASE_URL);
console.log('当前主机:', window.location.host);

// 显示消息
function showMessage(message, type = 'info') {
    // 移除现有的消息
    const existingMessage = document.querySelector('.message');
    if (existingMessage) {
        existingMessage.remove();
    }
    
    const messageDiv = document.createElement('div');
    messageDiv.className = `message message-${type}`;
    messageDiv.textContent = message;
    
    // 插入到页面顶部
    const container = document.querySelector('.container');
    if (container) {
        container.insertBefore(messageDiv, container.firstChild);
        
        // 3秒后自动移除
        setTimeout(() => {
            if (messageDiv.parentNode) {
                messageDiv.parentNode.removeChild(messageDiv);
            }
        }, 3000);
    }
}

// 显示加载动画
function showLoading(container) {
    const loadingDiv = document.createElement('div');
    loadingDiv.className = 'loading-container';
    loadingDiv.innerHTML = '<div class="loading"></div><p>加载中...</p>';
    
    if (typeof container === 'string') {
        document.querySelector(container).appendChild(loadingDiv);
    } else {
        container.appendChild(loadingDiv);
    }
    
    return loadingDiv;
}

// 隐藏加载动画
function hideLoading(loadingDiv) {
    if (loadingDiv && loadingDiv.parentNode) {
        loadingDiv.parentNode.removeChild(loadingDiv);
    }
}

// AJAX请求封装
async function apiRequest(url, options = {}) {
    try {
        console.log('发起API请求:', url);
        console.log('完整URL:', window.location.origin + url);
        
        const response = await fetch(url, {
            headers: {
                'Content-Type': 'application/json',
                ...options.headers
            },
            ...options
        });
        
        console.log('API响应状态:', response.status, response.statusText);
        
        const data = await response.json();
        console.log('API响应数据:', data);
        
        if (!data.success) {
            throw new Error(data.message || '请求失败');
        }
        
        return data.data;
    } catch (error) {
        console.error('API请求失败:', error);
        console.error('错误详情:', error.stack);
        throw error;
    }
}

// 搜索功能
async function searchComic(query) {
    if (!query.trim()) {
        showMessage('请输入搜索内容', 'warning');
        return;
    }
    
    try {
        // 判断是JM号还是关键词
        if (/^\d+$/.test(query.trim())) {
            // JM号搜索
            console.log('执行JM号搜索:', query.trim());
            const apiUrl = `/api/search/jm/${query.trim()}`;
            console.log('JM号搜索API URL:', apiUrl);
            const comic = await apiRequest(apiUrl);
            console.log('JM号搜索结果:', comic);
            if (comic) {
                window.location.href = `/detail/${query.trim()}`;
            }
        } else {
            // 关键词搜索
            console.log('执行关键词搜索:', query);
            const apiUrl = `/api/search/keyword?keyword=${encodeURIComponent(query)}`;
            console.log('关键词搜索API URL:', apiUrl);
            const results = await apiRequest(apiUrl);
            console.log('关键词搜索结果数量:', results ? results.length : 0);
            window.location.href = `/search?keyword=${encodeURIComponent(query)}`;
        }
    } catch (error) {
        console.error('搜索失败:', error);
        showMessage('搜索失败: ' + error.message, 'error');
    }
}

// 下载功能
async function downloadComic(jmId) {
    try {
        showMessage('开始下载，请稍候...', 'info');
        
        const response = await fetch(`${API_BASE_URL}/download/${jmId}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            }
        });
        
        const data = await response.json();
        
        if (data.success) {
            showMessage('下载任务已启动', 'success');
            
            // 开始监控下载进度
            monitorDownloadProgress(data.download_id);
        } else {
            if (data.downloaded) {
                if (confirm('该漫画已下载，是否重新下载？')) {
                    // 重新下载
                    // 这里可以添加重新下载的逻辑
                    showMessage('重新下载功能开发中...', 'info');
                }
            } else {
                showMessage(data.message, 'error');
            }
        }
    } catch (error) {
        showMessage('下载失败: ' + error.message, 'error');
    }
}

// 监控下载进度
function monitorDownloadProgress(downloadId) {
    const progressInterval = setInterval(async () => {
        try {
            const progress = await apiRequest(`${API_BASE_URL}/download/progress/${downloadId}`);
            
            if (progress.status === 'completed') {
                showMessage('下载完成！', 'success');
                clearInterval(progressInterval);
                
                // 刷新页面或更新状态
                setTimeout(() => {
                    location.reload();
                }, 2000);
            } else if (progress.status === 'error') {
                showMessage('下载失败: ' + progress.message, 'error');
                clearInterval(progressInterval);
            } else {
                // 更新进度显示
                updateProgressDisplay(progress);
            }
        } catch (error) {
            console.error('获取下载进度失败:', error);
            clearInterval(progressInterval);
        }
    }, 3000); // 每3秒更新一次
}

// 更新进度显示
function updateProgressDisplay(progress) {
    const progressContainer = document.querySelector('.download-progress');
    if (progressContainer) {
        const progressBar = progressContainer.querySelector('.progress-bar');
        const progressText = progressContainer.querySelector('.progress-text');
        
        if (progressBar) {
            progressBar.style.width = progress.progress + '%';
        }
        
        if (progressText) {
            progressText.textContent = progress.message;
        }
    }
}

// 删除漫画
async function deleteComic(jmId) {
    if (!confirm('确认删除该漫画？删除后不可恢复')) {
        return;
    }
    
    try {
        const response = await fetch(`${API_BASE_URL}/delete/${jmId}`, {
            method: 'DELETE'
        });
        
        const data = await response.json();
        
        if (data.success) {
            showMessage('删除成功', 'success');
            
            // 刷新列表
            setTimeout(() => {
                location.reload();
            }, 1000);
        } else {
            showMessage(data.message, 'error');
        }
    } catch (error) {
        showMessage('删除失败: ' + error.message, 'error');
    }
}

// 阅读功能
function startReading(jmId) {
    window.location.href = `/reader/${jmId}`;
}

// 页面跳转
function navigateTo(page) {
    window.location.href = page;
}

// 返回上一页
function goBack() {
    window.history.back();
}

// 格式化数字
function formatNumber(num) {
    if (num >= 10000) {
        return (num / 10000).toFixed(1) + '万';
    }
    return num.toString();
}

// 格式化时间
function formatTime(timeString) {
    const date = new Date(timeString);
    return date.toLocaleString('zh-CN');
}

// 防抖函数
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// UI/UX Pro Max 高级交互系统
// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    // 初始化所有高级功能
    initAdvancedFeatures();
    
    // 搜索框事件绑定
    const searchInput = document.getElementById('searchInput');
    const searchBtn = document.getElementById('searchBtn');
    
    if (searchInput && searchBtn) {
        // 回车搜索
        searchInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                searchComic(this.value);
            }
        });
        
        // 点击搜索
        searchBtn.addEventListener('click', function() {
            searchComic(searchInput.value);
        });
        
        // 实时搜索建议
        searchInput.addEventListener('input', debounce(function(e) {
            showSearchSuggestions(e.target.value);
        }, 300));
    }
    
    // 返回按钮事件绑定
    const backBtns = document.querySelectorAll('.back-btn');
    backBtns.forEach(btn => {
        btn.addEventListener('click', goBack);
    });
    
    // 键盘快捷键
    initKeyboardShortcuts();
    
    // 无障碍焦点管理
    initFocusManagement();
    
    // 视差滚动效果
    initParallax();
    
    // 页面加载完成动画
    document.body.style.animation = 'pageLoad 0.8s cubic-bezier(0.34, 1.56, 0.64, 1)';
    
    console.log('JM漫画阅读器已初始化 - UI/UX Pro Max版本');
});

// 高级功能初始化
function initAdvancedFeatures() {
    // 添加波纹效果到所有交互元素
    const interactiveElements = document.querySelectorAll('.btn, .feature-card, .comic-card');
    interactiveElements.forEach(element => {
        element.addEventListener('click', createRipple);
    });
    
    // 添加悬停音效（可选）
    addHoverEffects();
    
    // 初始化滚动指示器
    initScrollIndicator();
}

// 波纹效果
function createRipple(event) {
    const button = event.currentTarget;
    const ripple = document.createElement('span');
    const rect = button.getBoundingClientRect();
    const size = Math.max(rect.width, rect.height);
    const x = event.clientX - rect.left - size / 2;
    const y = event.clientY - rect.top - size / 2;
    
    ripple.style.width = ripple.style.height = size + 'px';
    ripple.style.left = x + 'px';
    ripple.style.top = y + 'px';
    ripple.classList.add('ripple');
    
    button.style.position = 'relative';
    button.style.overflow = 'hidden';
    button.appendChild(ripple);
    
    setTimeout(() => {
        ripple.remove();
    }, 600);
}

// 键盘快捷键系统
function initKeyboardShortcuts() {
    document.addEventListener('keydown', (e) => {
        // 全局快捷键
        if (e.ctrlKey || e.metaKey) {
            switch(e.key) {
                case 'k':
                    e.preventDefault();
                    document.getElementById('searchInput')?.focus();
                    break;
                case 'r':
                    e.preventDefault();
                    location.reload();
                    break;
                case 'b':
                    e.preventDefault();
                    goBack();
                    break;
            }
        }
        
        // 阅读器快捷键
        if (window.location.pathname.includes('/reader')) {
            handleReaderShortcuts(e);
        }
    });
}

// 阅读器快捷键处理
function handleReaderShortcuts(e) {
    switch(e.key) {
        case 'ArrowLeft':
        case 'a':
            e.preventDefault();
            previousPage();
            break;
        case 'ArrowRight':
        case 'd':
            e.preventDefault();
            nextPage();
            break;
        case 'f':
            e.preventDefault();
            toggleFullscreen();
            break;
        case 'Escape':
            if (document.fullscreenElement) {
                document.exitFullscreen();
            } else {
                goBack();
            }
            break;
        case '+':
        case '=':
            e.preventDefault();
            zoomIn();
            break;
        case '-':
        case '_':
            e.preventDefault();
            zoomOut();
            break;
    }
}

// 无障碍焦点管理
function initFocusManagement() {
    const focusableElements = document.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
    
    focusableElements.forEach(element => {
        element.addEventListener('focus', () => {
            element.style.outline = '2px solid #667eea';
            element.style.outlineOffset = '2px';
        });
        
        element.addEventListener('blur', () => {
            element.style.outline = 'none';
        });
    });
}

// 视差滚动效果
function initParallax() {
    const cards = document.querySelectorAll('.feature-card, .comic-card');
    
    window.addEventListener('scroll', throttle(() => {
        const scrolled = window.pageYOffset;
        
        cards.forEach((card, index) => {
            const speed = 0.1 + (index * 0.05);
            const yPos = -(scrolled * speed);
            card.style.transform = `translateY(${yPos}px)`;
        });
    }, 16));
}

// 滚动指示器
function initScrollIndicator() {
    const scrollIndicator = document.createElement('div');
    scrollIndicator.style.cssText = `
        position: fixed;
        top: 0;
        left: 0;
        width: 100%;
        height: 3px;
        background: var(--primary-gradient);
        transform-origin: left;
        transform: scaleX(0);
        z-index: 9999;
        transition: transform 0.1s ease;
    `;
    document.body.appendChild(scrollIndicator);
    
    window.addEventListener('scroll', () => {
        const scrolled = (window.scrollY / (document.documentElement.scrollHeight - window.innerHeight)) * 100;
        scrollIndicator.style.transform = `scaleX(${scrolled / 100})`;
    });
}

// 搜索建议
function showSearchSuggestions(query) {
    if (!query.trim()) return;
    
    // 这里可以添加实际的搜索建议API调用
    console.log('搜索建议:', query);
}

// 悬停效果增强
function addHoverEffects() {
    const cards = document.querySelectorAll('.feature-card, .comic-card');
    
    cards.forEach(card => {
        card.addEventListener('mouseenter', () => {
            card.style.transform = 'translateY(-12px) scale(1.02)';
        });
        
        card.addEventListener('mouseleave', () => {
            card.style.transform = 'translateY(0) scale(1)';
        });
    });
}

// 平滑滚动到顶部
function scrollToTop() {
    window.scrollTo({
        top: 0,
        behavior: 'smooth'
    });
}