#!/usr/bin/env node
import * as fs from 'fs'
import * as path from 'path'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const repoRoot = path.resolve(__dirname, '..')
const simDir = path.join(repoRoot, 'sim')
const versionPath = path.join(__dirname, 'sim-version.json')

function readJson(filePath) {
  return JSON.parse(fs.readFileSync(filePath, 'utf8'))
}

function getVersion() {
  const arg = process.argv[2]
  if (arg) return arg
  const config = readJson(versionPath)
  if (!config.simulator) throw new Error('No simulator version in scripts/sim-version.json')
  return config.simulator
}

async function downloadText(url) {
  const response = await fetch(url)
  if (!response.ok) throw new Error(`Failed to download ${url}: ${response.status}`)
  return response.text()
}

async function downloadSimulator(version) {
  const simUrl = `https://trg-arcade.userpxt.io/v${version}/---simulator`
  const baseUrl = `https://trg-arcade.userpxt.io/v${version}`
  const outputDir = path.join(repoRoot, '.tmp-sim')
  fs.rmSync(outputDir, { recursive: true, force: true })
  fs.mkdirSync(outputDir, { recursive: true })

  const indexHtml = await downloadText(simUrl)
  const patchedHtml = indexHtml.replace(/https:\/\/cdn\.makecode\.com\//g, './cdn/')
  fs.writeFileSync(path.join(outputDir, 'index.html'), patchedHtml)

  const resources = new Set()
  let match
  const scriptRegex = /<script[^>]+src="([^"]+)"/g
  const linkRegex = /<link[^>]+href="([^"]+)"/g
  while ((match = scriptRegex.exec(indexHtml)) !== null) resources.add(match[1])
  while ((match = linkRegex.exec(indexHtml)) !== null) resources.add(match[1])

  for (const resource of resources) {
    if (resource.startsWith('data:')) continue
    let resourceUrl, resourcePath
    if (resource.startsWith('https://cdn.makecode.com')) {
      const cdnPath = resource.replace('https://cdn.makecode.com/', '')
      resourceUrl = resource
      resourcePath = path.join(outputDir, 'cdn', cdnPath)
    } else if (resource.startsWith('/')) {
      resourceUrl = `https://trg-arcade.userpxt.io${resource}`
      resourcePath = path.join(outputDir, resource.slice(1))
    } else {
      resourceUrl = `${baseUrl}/${resource}`
      resourcePath = path.join(outputDir, resource)
    }
    fs.mkdirSync(path.dirname(resourcePath), { recursive: true })
    fs.writeFileSync(resourcePath, await downloadText(resourceUrl))
  }

  return outputDir
}

function extractHashes(indexHtml) {
  const hashes = {}
  const patterns = {
    'sim.css': /href="[^"]*\/cdn\/blob\/([a-f0-9]+)\/sim\.css"/,
    'icons.css': /href="[^"]*\/cdn\/blob\/([a-f0-9]+)\/icons\.css"/,
    'pxtsim.js': /src="[^"]*\/cdn\/blob\/([a-f0-9]+)\/pxtsim\.js"/,
    'sim.js': /src="[^"]*\/cdn\/blob\/([a-f0-9]+)\/sim\.js"/,
  }
  for (const [filename, regex] of Object.entries(patterns)) {
    const m = indexHtml.match(regex)
    if (!m) throw new Error(`Could not find hash for ${filename} in downloaded index.html`)
    hashes[filename] = m[1]
  }
  return hashes
}

function findMakeWebSim(version) {
  const candidate = path.resolve(repoRoot, '..', 'make-web', 'public', 'simulator', version)
  return fs.existsSync(candidate) ? candidate : null
}

function copyBlobFiles(sourceDir, hashes) {
  const cdnDir = path.join(simDir, 'cdn', 'blob')
  for (const [filename, hash] of Object.entries(hashes)) {
    const src = path.join(sourceDir, 'cdn', 'blob', hash, filename)
    const dstDir = path.join(cdnDir, hash)
    fs.mkdirSync(dstDir, { recursive: true })
    fs.copyFileSync(src, path.join(dstDir, filename))
  }
}

function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
}

function updateHtmlReferences(hashes) {
  const files = ['index.html', 'slim.html', 'webgpu.html', 'slim-webgpu.html']
  for (const name of files) {
    const filePath = path.join(simDir, name)
    let content = fs.readFileSync(filePath, 'utf8')
    for (const [filename, hash] of Object.entries(hashes)) {
      const escaped = escapeRegex(filename)
      const regex = new RegExp(`(href|src)="\\./cdn/blob/[a-f0-9]+/${escaped}"`, 'g')
      content = content.replace(regex, `$1="./cdn/blob/${hash}/${filename}"`)
    }
    fs.writeFileSync(filePath, content)
  }
}

function updatePlayHtml(version) {
  const filePath = path.join(repoRoot, 'public', 'play.html')
  let content = fs.readFileSync(filePath, 'utf8')
  content = content.replace(/targetVersion: "[^"]+"/g, `targetVersion: "${version}"`)
  content = content.replace(/version: meta\.targetVersion \|\| "[^"]+"/g, `version: meta.targetVersion || "${version}"`)
  fs.writeFileSync(filePath, content)
}

function cleanupOldBlobs(hashes) {
  const cdnDir = path.join(simDir, 'cdn', 'blob')
  const referenced = new Set(Object.values(hashes))
  for (const dir of fs.readdirSync(cdnDir)) {
    const dirPath = path.join(cdnDir, dir)
    if (fs.statSync(dirPath).isDirectory() && !referenced.has(dir)) {
      fs.rmSync(dirPath, { recursive: true, force: true })
    }
  }
}

function writeVersion(version) {
  fs.writeFileSync(versionPath, JSON.stringify({ simulator: version }, null, 2) + '\n')
}

async function main() {
  const version = getVersion()
  console.log(`Updating simulator to ${version}...`)

  let sourceDir = findMakeWebSim(version)
  let downloaded = false
  if (sourceDir) {
    console.log(`Using make-web simulator: ${sourceDir}`)
  } else {
    console.log('make-web simulator not found, downloading from CDN...')
    sourceDir = await downloadSimulator(version)
    downloaded = true
  }

  const indexHtml = fs.readFileSync(path.join(sourceDir, 'index.html'), 'utf8')
  const hashes = extractHashes(indexHtml)

  copyBlobFiles(sourceDir, hashes)
  updateHtmlReferences(hashes)
  updatePlayHtml(version)
  writeVersion(version)
  cleanupOldBlobs(hashes)

  if (downloaded) {
    fs.rmSync(sourceDir, { recursive: true, force: true })
  }

  console.log(`Simulator updated to ${version}`)
}

main().catch((err) => {
  console.error(err)
  process.exit(1)
})
