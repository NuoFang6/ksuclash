/* KSU Clash 悬浮面板 - 注入 zashboard
 *  - 可拖拽气泡，点按展开全屏覆盖层（核心操作）
 *  - 启动/停止/重启 经 window.ksu.exec 调用模块 clashctl（KSU 管理器 WebUI 或配套 App 内可用；
 *    普通浏览器自动降级为仅状态显示）
 *  - 启动/重启成功后自动刷新页面（zashboard 重连）；停止后覆盖层显示"核心未运行"
 *  - 首次访问自动导入后端（读取 window.__KSUCLASH__ 注入的 API 地址与 secret）
 */
;(function () {
  'use strict'
  var CFG = window.__KSUCLASH__ || { api: { protocol: 'http', host: '127.0.0.1', port: '9090', secret: '' } }
  var A = CFG.api
  var hasRoot = typeof window.ksu !== 'undefined' && typeof window.ksu.exec === 'function'
  var CTL = '/data/adb/modules/ksuclash/scripts/clashctl'

  // ---------- 自动导入后端（仅当面板尚未配置任何后端时；旧空密钥条目自动修复） ----------
  function seedBackend() {
    try {
      var list = JSON.parse(localStorage.getItem('setup/api-list') || '[]')
      if (list.length) {
        for (var i = 0; i < list.length; i++) {
          if (list[i].uuid === 'ksuclash-local' && A.secret && list[i].password !== A.secret) {
            list[i].password = A.secret
            localStorage.setItem('setup/api-list', JSON.stringify(list))
          }
        }
        return
      }
      var backend = {
        type: 'clash',
        protocol: A.protocol || 'http',
        host: A.host || '127.0.0.1',
        port: String(A.port || '9090'),
        secondaryPath: '',
        password: A.secret || '',
        uuid: 'ksuclash-local',
        label: 'KSU Clash',
      }
      localStorage.setItem('setup/api-list', JSON.stringify([backend]))
      localStorage.setItem('setup/active-uuid', JSON.stringify('ksuclash-local'))
    } catch (e) { /* ignore */ }
  }
  seedBackend()

  // ---------- root 执行 ----------
  function rootExec(cmd) {
    if (!hasRoot) return Promise.reject(new Error('no root bridge'))
    return new Promise(function (resolve) {
      var out = ''
      try { out = window.ksu.exec(cmd) || '' } catch (e) { out = '' }
      resolve(out)
    })
  }

  function getState() {
    return rootExec(CTL + ' status').then(function (out) {
      var m = (out || '').match(/state=(\w+)/)
      return m ? m[1] : (hasRoot ? 'off' : 'unknown')
    })
  }
  function waitRunning(sec) {
    return getState().then(function (st) {
      if (st === 'on') return true
      if (sec <= 0) return false
      return new Promise(function (res) { setTimeout(function () { res(waitRunning(sec - 2)) }, 2000) })
    })
  }

  // ---------- UI ----------
  var css = document.createElement('style')
  css.textContent = [
    '#ksuc-bubble{position:fixed;z-index:2147483647;right:14px;bottom:96px;width:44px;height:44px;',
    'border-radius:50%;background:#1f2937;color:#fbbf24;display:flex;align-items:center;justify-content:center;',
    'font-size:19px;box-shadow:0 2px 10px rgba(0,0,0,.35);cursor:grab;user-select:none;touch-action:none;opacity:.85}',
    '#ksuc-bubble:active{cursor:grabbing;opacity:1}',
    '@media (prefers-color-scheme: light){#ksuc-card{background:#ffffff !important;color:#0f172a !important}',
    '#ksuc-card .ksuc-btn{background:#e2e8f0 !important;color:#0f172a !important}',
    '#ksuc-card .ksuc-btn.pri{background:#2563eb !important;color:#fff !important}',
    '#ksuc-card .ksuc-btn.warn{background:#b91c1c !important;color:#fff !important}}',
    '#ksuc-ov{position:fixed;inset:0;z-index:2147483646;background:rgba(0,0,0,.55);display:none;',
    'align-items:center;justify-content:center}',
    '#ksuc-ov.show{display:flex}',
    '#ksuc-card{width:270px;background:#1f2937;color:#e5e7eb;border-radius:18px;padding:20px;',
    'box-shadow:0 10px 40px rgba(0,0,0,.45);font-size:14px}',
    '.ksuc-title{font-weight:700;font-size:16px;display:flex;align-items:center;gap:8px}',
    '.ksuc-title .tag{font-size:11px;background:#334155;color:#cbd5e1;border-radius:99px;padding:2px 8px;font-weight:400}',
    '.ksuc-status{margin:12px 0 4px;font-size:13px;line-height:1.5;word-break:break-all}',
    '.ksuc-dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;background:#9ca3af;vertical-align:middle}',
    '.ksuc-dot.on{background:#22c55e}.ksuc-dot.panic{background:#ef4444}',
    '.ksuc-row{display:flex;gap:8px;margin-top:12px}',
    '.ksuc-btn{flex:1;padding:11px 0;border-radius:10px;border:none;font-size:13.5px;cursor:pointer;',
    'background:#334155;color:#e5e7eb;font-weight:600}',
    '.ksuc-btn.pri{background:#2563eb;color:#fff}',
    '.ksuc-btn.warn{background:#b91c1c;color:#fff}',
    '.ksuc-btn:active{filter:brightness(1.25)}',
    '.ksuc-hint{font-size:11.5px;opacity:.6;margin-top:10px;line-height:1.6}',
    '.ksuc-big{font-size:15px;font-weight:700;margin:8px 0 2px}',
  ].join('')
  document.head.appendChild(css)

  var bubble = document.createElement('div')
  bubble.id = 'ksuc-bubble'
  bubble.textContent = '⚡'
  var ov = document.createElement('div')
  ov.id = 'ksuc-ov'
  var card = document.createElement('div')
  card.id = 'ksuc-card'
  ov.appendChild(card)
  document.body.appendChild(bubble)
  document.body.appendChild(ov)

  function html() {
    return '<div class="ksuc-title">⚡ KSU Clash <span class="tag">mihomo</span></div>' +
      '<div class="ksuc-status" id="ksuc-st">读取中…</div>' +
      '<div id="ksuc-ctl"></div>' +
      '<div class="ksuc-hint">拖动气泡可移动位置；核心操作经 root 桥执行。</div>'
  }

  // 视图：running=控制按钮; stopped=核心未运行提示
  function renderRunning(st) {
    var stEl = card.querySelector('#ksuc-st')
    var ctl = card.querySelector('#ksuc-ctl')
    var dot = st === 'on' ? 'on' : (st === 'panic' ? 'panic' : '')
    var label = { on: '核心运行中', off: '核心未运行', starting: '启动中…', stopping: '停止中…', panic: '已熔断（反复异常）', unknown: '状态未知' }[st] || st
    stEl.innerHTML = '<span class="ksuc-dot ' + dot + '"></span>' + label
    if (!hasRoot) {
      ctl.innerHTML = '<div class="ksuc-hint">当前环境无 root 桥，仅显示状态。核心管理请使用 KSU Clash App。</div>'
      return
    }
    if (st === 'on') {
      ctl.innerHTML = '<div class="ksuc-row">' +
        '<button class="ksuc-btn" data-a="restart">重启核心</button>' +
        '<button class="ksuc-btn warn" data-a="stop">停止</button></div>'
    } else if (st === 'panic') {
      ctl.innerHTML = '<div class="ksuc-row"><button class="ksuc-btn pri" data-a="resume">恢复并启动</button></div>'
    } else {
      ctl.innerHTML = '<div class="ksuc-row"><button class="ksuc-btn pri" data-a="start">启动核心</button></div>'
    }
  }

  function renderBusy(text) {
    card.querySelector('#ksuc-st').innerHTML = '<span class="ksuc-dot"></span>' + text
    card.querySelector('#ksuc-ctl').innerHTML = ''
  }

  function renderStopped() {
    var stEl = card.querySelector('#ksuc-st')
    var ctl = card.querySelector('#ksuc-ctl')
    stEl.innerHTML = '<span class="ksuc-dot"></span>核心未运行'
    ctl.innerHTML = '<div class="ksuc-big">zashboard 面板不可用</div>' +
      '<div class="ksuc-hint">核心停止后页面将无法连接后端。可点击下方按钮重新启动，完成后自动刷新。</div>' +
      '<div class="ksuc-row">' +
      (hasRoot ? '<button class="ksuc-btn pri" data-a="start">启动核心</button>' : '') +
      '<button class="ksuc-btn" data-a="close">关闭</button></div>'
  }

  function refresh() {
    getState().then(function (st) {
      if (st === 'off') renderStopped()
      else renderRunning(st)
    })
  }

  function act(a) {
    if (!hasRoot) return
    if (a === 'close') { ov.classList.remove('show'); return }
    if (a === 'stop') {
      renderBusy('停止中…')
      rootExec(CTL + ' stop').then(function () { setTimeout(refresh, 500) })
      return
    }
    // start / resume / restart：完成后刷新 zash 面板
    var cmd = a === 'resume' ? 'resume' : a
    renderBusy(cmd === 'restart' ? '重启中…' : '启动中…')
    rootExec(CTL + ' ' + cmd).then(function () {
      waitRunning(35).then(function (ok) {
        if (ok) {
          renderBusy('已启动，正在刷新面板…')
          setTimeout(function () { location.reload() }, 600)
        } else {
          refresh()
        }
      })
    })
  }

  bubble.addEventListener('click', function (e) {
    if (dragged) return
    if (!card.innerHTML) card.innerHTML = html()
    ov.classList.add('show')
    refresh()
  })
  ov.addEventListener('click', function (e) {
    if (e.target === ov) { ov.classList.remove('show'); return }
    var t = e.target
    if (t.dataset && t.dataset.a) act(t.dataset.a)
  })

  // ---------- 拖拽（保存位置） ----------
  var dragged = false
  var sx = 0, sy = 0, ox = 0, oy = 0, moved = false
  bubble.addEventListener('pointerdown', function (e) {
    sx = e.clientX; sy = e.clientY
    var r = bubble.getBoundingClientRect()
    ox = r.left; oy = r.top
    moved = false
    bubble.setPointerCapture(e.pointerId)
  })
  bubble.addEventListener('pointermove', function (e) {
    if (e.buttons === 0 && e.pointerType === 'mouse') return
    var dx = e.clientX - sx, dy = e.clientY - sy
    if (Math.abs(dx) + Math.abs(dy) > 6) { moved = true; dragged = true }
    if (moved) {
      var w = window.innerWidth, h = window.innerHeight
      var x = Math.min(Math.max(0, ox + dx), w - 46)
      var y = Math.min(Math.max(0, oy + dy), h - 46)
      bubble.style.right = 'auto'
      bubble.style.bottom = 'auto'
      bubble.style.left = x + 'px'
      bubble.style.top = y + 'px'
    }
  })
  bubble.addEventListener('pointerup', function () {
    if (moved) {
      try { localStorage.setItem('ksuc-panel-pos', bubble.style.left + '|' + bubble.style.top) } catch (e) {}
      setTimeout(function () { dragged = false }, 50)
    }
  })
  try {
    var pos = (localStorage.getItem('ksuc-panel-pos') || '').split('|')
    if (pos.length === 2 && pos[0]) {
      bubble.style.right = 'auto'; bubble.style.bottom = 'auto'
      bubble.style.left = pos[0]; bubble.style.top = pos[1]
    }
  } catch (e) {}
})()
