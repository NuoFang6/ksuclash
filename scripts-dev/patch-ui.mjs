#!/usr/bin/env node
/**
 * patch-ui.mjs — 将 zashboard 构建产物打包进模块 ui/ 目录并注入悬浮面板
 * 用法: node patch-ui.mjs <zashboard-dist> <module-root>
 */
import { cpSync, existsSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs'
import { join } from 'node:path'

const [dist, modRoot] = process.argv.slice(2)
if (!dist || !modRoot) {
  console.error('usage: node patch-ui.mjs <zashboard-dist> <module-root>')
  process.exit(1)
}
const uiDir = join(modRoot, 'ui')
const panelSrc = join(modRoot, 'webroot-src')

if (!existsSync(join(dist, 'index.html'))) {
  console.error(`dist index.html not found in ${dist}`)
  process.exit(1)
}

rmSync(uiDir, { recursive: true, force: true })
mkdirSync(uiDir, { recursive: true })
cpSync(dist, uiDir, { recursive: true })
cpSync(join(panelSrc, 'panel.js'), join(uiDir, 'panel.js'))

// 注入悬浮面板：放在应用入口之前执行（classic script 先于 module script）
let html = readFileSync(join(uiDir, 'index.html'), 'utf8')
const inject =
  '<script src="./panel-config.js"></script>\n' +
  '<script src="./panel.js"></script>\n'
if (!html.includes('panel.js')) {
  if (html.includes('</body>')) {
    html = html.replace('</body>', inject + '</body>')
  } else {
    html += inject
  }
  writeFileSync(join(uiDir, 'index.html'), html)
}

// 默认 panel-config（设备端每次启动会被 patch_config.sh 按用户配置重写）
writeFileSync(
  join(uiDir, 'panel-config.js'),
  'window.__KSUCLASH__={api:{protocol:"http",host:"127.0.0.1",port:"9090",secret:""}};\n',
)

console.log(`ui packaged: ${uiDir}`)
