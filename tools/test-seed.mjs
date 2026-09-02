import { readFileSync } from 'node:fs'
const src = readFileSync('module/ui/panel.js', 'utf8')
// 抽取 seedBackend 及其依赖的 SEED_VER 常量
const m = src.match(/var SEED_VER = '[^']*'\n  function seedBackend\(\) \{[\s\S]*?\n  \}\n  seedBackend\(\)/)
if (!m) { console.error('seedBackend not found'); process.exit(1) }
const fnSrc = m[0].replace(/\n  seedBackend\(\)$/, '')

const store = {}
const localStorage = {
  getItem: (k) => (k in store ? store[k] : null),
  setItem: (k, v) => { store[k] = String(v) },
}
// 注意：panel.js 中 A = CFG.api，A 本身就是 {protocol,host,port,secret}
const A = { protocol: 'http', host: '127.0.0.1', port: '9090', secret: '' }

function reset() { for (const k in store) delete store[k] }
function list() { return JSON.parse(store['setup/api-list'] || '[]') }
function run(label) {
  const fn = new Function('localStorage', 'A', 'JSON', fnSrc + '\nreturn seedBackend')
  fn(localStorage, A, JSON)()
  const after = list()
  console.log(`[${label}] 条目数=${after.length} ->`, after.map((x) => `${x.uuid}|${x.label}`).join(', '), '| active=', store['setup/active-uuid'], '| flag=', store['setup/suclash-seed-v'])
  return after
}
const local = () => ({ type:'clash', protocol:'http', host:'127.0.0.1', port:'9090', secondaryPath:'', password:'', uuid:'suclash-local', label:'SU Clash', disableUpgradeCore:false, disableTunMode:false })

// 关键约定（对齐 zashboard 的 VueUse useStorage 序列化器）：
//   api-list      默认 []  -> object 序列化器 -> JSON 存取
//   active-uuid   默认 ''  -> string 序列化器 -> raw 存取（绝不能 JSON.stringify）

// 场景1：空列表 → 种入 + 迁移标记 + active-uuid 为 raw
reset()
let a = run('空列表种入')
if (a.length !== 1 || a[0].uuid !== 'suclash-local') process.exit(2)
if (store['setup/suclash-seed-v'] !== '2') process.exit(3)
if (store['setup/active-uuid'] !== 'suclash-local') process.exit(4) // raw，非 JSON

// 场景2：污染态（迁移未完成）→ 一次性去重 + 激活纠正（raw）
reset()
store['setup/api-list'] = JSON.stringify([
  local(),
  { type:'clash', protocol:'http', host:'127.0.0.1', port:'9090', secondaryPath:'', password:'', uuid:'dup-1', label:'SUClash' },
])
store['setup/active-uuid'] = 'dup-1'
a = run('污染态去重(迁移)')
if (a.length !== 1 || a[0].uuid !== 'suclash-local') process.exit(5)
if (store['setup/active-uuid'] !== 'suclash-local') process.exit(6)
if (store['setup/suclash-seed-v'] !== '2') process.exit(7)

// 场景3：保留远程后端，且不打断其激活
reset()
store['setup/api-list'] = JSON.stringify([
  { type:'clash', protocol:'https', host:'1.2.3.4', port:'8443', secondaryPath:'', password:'x', uuid:'remote-1', label:'Remote' },
  local(),
  { type:'clash', protocol:'http', host:'127.0.0.1', port:'9090', secondaryPath:'', password:'', uuid:'dup-2', label:'SUClash' },
])
store['setup/active-uuid'] = 'remote-1'
a = run('保留远程+去重(迁移)')
if (a.length !== 2) process.exit(8)
if (!a.find((x) => x.uuid === 'remote-1')) process.exit(9)
if (a.find((x) => x.uuid === 'dup-2')) process.exit(10)
if (store['setup/active-uuid'] !== 'remote-1') process.exit(11)

// 场景4：迁移已完成 → 不再执行去重（同 endpoint 条目被保留）
reset()
store['setup/api-list'] = JSON.stringify([
  local(),
  { type:'clash', protocol:'http', host:'127.0.0.1', port:'9090', secondaryPath:'', password:'', uuid:'should-remain', label:'SU Clash', disableUpgradeCore:false, disableTunMode:false },
])
store['setup/active-uuid'] = 'suclash-local'
store['setup/suclash-seed-v'] = '2'
a = run('迁移后不再去重')
if (a.length !== 2) process.exit(12)
if (!a.find((x) => x.uuid === 'should-remain')) process.exit(13)

// 场景5：secret 变更 → suclash-local 密码被同步
reset()
const A2 = { protocol: 'http', host: '127.0.0.1', port: '9090', secret: 'new-secret' }
store['setup/api-list'] = JSON.stringify([{ ...local(), password: '' }])
store['setup/active-uuid'] = 'suclash-local'
store['setup/suclash-seed-v'] = '2'
new Function('localStorage', 'A', 'JSON', fnSrc + '\nreturn seedBackend')(localStorage, A2, JSON)()
a = list()
if (a.length !== 1 || a[0].password !== 'new-secret') process.exit(14)

// 场景6：zashboard 路由守卫视角 —— 首次进入（无任何数据）后，activeBackend 必须能解析
reset()
new Function('localStorage', 'A', 'JSON', fnSrc + '\nreturn seedBackend')(localStorage, A, JSON)()
{
  // 复刻 zashboard store/setup.ts 的读取方式
  const backendList = JSON.parse(store['setup/api-list'])       // object 序列化器
  const activeUuid = store['setup/active-uuid']                  // string 序列化器 -> raw
  const activeBackend = backendList.find((b) => b.uuid === activeUuid)
  console.log(`[场景6] activeUuid=${JSON.stringify(activeUuid)} -> activeBackend=${activeBackend ? activeBackend.uuid : 'null'}`)
  if (!activeBackend || activeBackend.uuid !== 'suclash-local') {
    console.error('  路由守卫会误判 !activeBackend -> 跳登录页')
    process.exit(15)
  }
}

console.log('ALL PASS')
