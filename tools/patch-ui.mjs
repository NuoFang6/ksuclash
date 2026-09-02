#!/usr/bin/env node
/**
 * patch-ui.mjs — 将 zashboard 构建产物原样打包进模块 ui/ 目录（零修改）
 *
 * 面板注入已移至 mihomo 服务端（mihomo-patches/0005-serve-ui-panel.patch）：
 * /ui/* 的 text/html 响应在运行时注入悬浮面板，panel.js 内嵌于核心二进制。
 * 因此本脚本不再改动 index.html，也不再写入 panel.js / panel-config.js，
 * zashboard 官方「升级面板」覆盖目录后注入依然生效。
 *
 * 用法: node tools/patch-ui.mjs [zashboard-dist] [module-root]
 *   [zashboard-dist]  默认 tmp/zashboard（get-zashboard.sh 的下载解压目录）
 *   [module-root]     默认 module/
 */
import { cpSync, existsSync, mkdirSync, rmSync } from 'node:fs'
import { join } from 'node:path'

const dist = process.argv[2] || 'tmp/zashboard'
const modRoot = process.argv[3] || 'module'
const uiDir = join(modRoot, 'ui')

if (!existsSync(join(dist, 'index.html'))) {
  console.error(`dist index.html not found in ${dist}`)
  process.exit(1)
}

rmSync(uiDir, { recursive: true, force: true })
mkdirSync(uiDir, { recursive: true })
cpSync(dist, uiDir, { recursive: true })

console.log(`ui packaged (unmodified zashboard dist): ${uiDir}`)
