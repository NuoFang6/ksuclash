/* KSU Clash 悬浮面板 - 注入 zashboard
 * 功能：
 *  - 可拖拽气泡，点按展开面板
 *  - 核心操作（启动/停止/重启/状态）经 window.ksu.exec 调用模块 clashctl（仅 KSU 管理器 WebUI 内可用）
 *  - 快速模式切换（规则/全局/直连）优先走 clashctl，浏览器环境降级为 Clash API
 *  - 首次访问自动填充后端（读取 window.__KSUCLASH__ 注入的 API 地址与 secret），免手动配置
 */
;(function () {
  'use strict'
  var CFG = window.__KSUCLASH__ || { api: { protocol: 'http', host: '127.0.0.1', port: '9090', secret: '' } }
  var A = CFG.api
  var hasRoot = typeof window.ksu !== 'undefined' && typeof window.ksu.exec === 'function'
  var CTL = '/data/adb/modules/ksuclash/scripts/clashctl'

  // ---------- 自动导入后端（仅当面板尚未配置任何后端时） ----------
  function seedBackend() {
    try {
      var list = JSON.parse(localStorage.getItem('setup/api-list') || '[]')
      if (list.length) {
        // 修复：先前以空密钥种子过的条目，配置就绪后自动补上 secret
        for (var i = 0; i < list.length; i++) {
          if (list[i].uuid === 'ksuclash-local' && A.secret && list[i].password !== A.secret) {
            list[i].password = A.secret
            localStorage.setItem('setup/api-list', JSON.stringify(list))
          }
        }
        return
      }
      var uuid = 'ksuclash-local'
      var backend = {
        type: 'clash',
        protocol: A.protocol || 'http',
        host: A.host || '127.0.0.1',
        port: String(A.port || '9090'),
        secondaryPath: '',
        password: A.secret || '',
        uuid: uuid,
        label: 'KSU Clash',
      }
      localStorage.setItem('setup/api-list', JSON.stringify([backend]))
      localStorage.setItem('setup/active-uuid', JSON.stringify(uuid))
    } catch (e) { /* ignore */ }
  }
  seedBackend()

  // ---------- API ----------
  function apiBase() { return A.protocol + '://' + A.host + ':' + A.port }
  function api(method, path, body) {
    return fetch(apiBase() + path, {
      method: method,
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + (A.secret || ''),
      },
      body: body ? JSON.stringify(body) : undefined,
    })
  }
  function rootExec(cmd) {
    if (!hasRoot) return Promise.reject(new Error('no root bridge'))
    return new Promise(function (resolve) {
      var out = window.ksu.exec(cmd)
      resolve(out || '')
    })
  }

  // ---------- UI ----------
  var css = document.createElement('style')
  css.textContent = [
    '#ksuc-panel-bubble{position:fixed;z-index:2147483647;right:14px;bottom:96px;width:44px;height:44px;',
    'border-radius:50%;background:#1f2937;color:#fbbf24;display:flex;align-items:center;justify-content:center;',
    'font-size:19px;box-shadow:0 2px 10px rgba(0,0,0,.35);cursor:grab;user-select:none;touch-action:none;',
    'opacity:.85;transition:opacity .2s;}#ksuc-panel-bubble:active{cursor:grabbing;opacity:1}',
    '#ksuc-panel-card{position:fixed;z-index:2147483647;right:8px;bottom:148px;width:230px;',
    'background:oklch(var(--b2,#1f2937));border-radius:14px;box-shadow:0 6px 24px rgba(0,0,0,.3);',
    'padding:12px 14px;font-size:13px;display:none;color:oklch(var(--bc,#e5e7eb))}',
    '#ksuc-panel-card.show{display:block}',
    '.ksuc-row{display:flex;gap:6px;margin-top:8px}',
    '.ksuc-btn{flex:1;padding:7px 0;border-radius:9px;border:none;font-size:12.5px;cursor:pointer;',
    'background:oklch(var(--pc,#3b82f6));color:#fff;font-weight:600}',
    '.ksuc-btn.warn{background:#b91c1c;color:#fff}',
    '.ksuc-btn.ghost{background:oklch(var(--bc,#94a3b8)/.12);color:oklch(var(--bc,#e5e7eb))}',
    '.ksuc-title{font-weight:700;margin-bottom:2px}',
    '.ksuc-status{font-size:11.5px;opacity:.75;word-break:break-all}',
    '.ksuc-dot{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:5px;background:#9ca3af}',
    '.ksuc-dot.on{background:#16a34a}.ksuc-dot.off{background:#9ca3af}.ksuc-dot.panic{background:#dc2626}',
  ].join('')
  document.head.appendChild(css)

  var bubble = document.createElement('div')
  bubble.id = 'ksuc-panel-bubble'
  bubble.textContent = '⚡'
  var card = document.createElement('div')
  card.id = 'ksuc-panel-card'
  card.innerHTML =
    '<div class="ksuc-title">KSU Clash</div>' +
    '<div class="ksuc-status" id="ksuc-status"><span class="ksuc-dot"></span>读取中…</div>' +
    '<div class="ksuc-row" id="ksuc-core-row">' +
    '<button class="ksuc-btn ghost" data-a="start">启动</button>' +
    '<button class="ksuc-btn warn" data-a="stop">停止</button>' +
    '<button class="ksuc-btn ghost" data-a="restart">重启</button>' +
    '</div>' +
    '<div class="ksuc-row">' +
    '<button class="ksuc-btn ghost" data-m="rule">规则</button>' +
    '<button class="ksuc-btn ghost" data-m="global">全局</button>' +
    '<button class="ksuc-btn ghost" data-m="direct">直连</button>' +
    '</div>'
  document.body.appendChild(bubble)
  document.body.appendChild(card)

  function $(id) { return document.getElementById(id) }

  function refresh() {
    rootExec(CTL + ' status')
      .catch(function () { return '' })
      .then(function (out) {
        var el = $('ksuc-status')
        if (out && out.indexOf('state=') >= 0) {
          var m = out.match(/state=(\w+)/)
          var st = m ? m[1] : 'off'
          var dot = st === 'on' ? 'on' : (st === 'panic' ? 'panic' : 'off')
          var label = { on: '运行中', off: '已停止', starting: '启动中', stopping: '停止中', panic: '熔断(看门狗)' }[st] || st
          var extra = ''
          var pm = out.match(/panel=(\S+)/)
          if (out.indexOf('pid=') >= 0) extra = (out.match(/pid=(-?\d+)/) || [])[1]
          el.innerHTML = '<span class="ksuc-dot ' + dot + '"></span>' + label +
            (extra && extra !== '-1' ? ' · pid ' + extra : '')
          $('ksuc-core-row').style.display = hasRoot ? 'flex' : 'none'
        } else if (hasRoot) {
          el.innerHTML = '<span class="ksuc-dot off"></span>clashctl 不可用'
        } else {
          el.innerHTML = '<span class="ksuc-dot"></span>浏览器模式: 仅模式切换'
        }
      })
  }

  function action(name) {
    if (!hasRoot) return
    rootExec(CTL + ' ' + name).then(function (out) { refresh() })
  }

  function mode(m) {
    if (hasRoot) {
      rootExec(CTL + ' mode ' + m).then(function () { refresh() })
    } else {
      api('PATCH', '/configs', { mode: m }).then(function () { refresh() }).catch(function () {})
    }
  }

  bubble.addEventListener('click', function (e) {
    if (dragged) return
    card.classList.toggle('show')
    if (card.classList.contains('show')) refresh()
  })

  card.addEventListener('click', function (e) {
    var t = e.target
    if (t.dataset && t.dataset.a) action(t.dataset.a)
    if (t.dataset && t.dataset.m) mode(t.dataset.m)
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

  // 初始刷新一次（若面板是展开状态）
  refresh()
  // 点击卡片外自动收起
  document.addEventListener('click', function (e) {
    if (!card.classList.contains('show')) return
    if (card.contains(e.target) || bubble.contains(e.target)) return
    card.classList.remove('show')
  }, true)
})()
