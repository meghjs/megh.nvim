-- Megh templates for Neovim: starts the Megh language server for `megh`
-- buffers and inserts closing tags after `>` or `/`.
local M = {}

local defaults = {
  -- Command that starts the server. nil: `node <plugin>/server/megh-language-server.js --stdio`.
  cmd = nil,
  -- Insert `</tag>` after typing `>` (and complete `</` after typing `/`).
  auto_close_tags = true,
  -- Sent to the server as `megh.*`, the same names as the VS Code settings.
  settings = {
    validate = { enable = true, html = true },
    -- HTML formatter options, as in VS Code's `html.format.*`
    -- (wrapLineLength, wrapAttributes, indentInnerHtml, ...).
    format = {},
  },
}

M.config = vim.deepcopy(defaults)

local function plugin_root()
  -- This file is <root>/lua/megh/init.lua.
  local here = debug.getinfo(1, 'S').source:sub(2)
  return vim.fn.fnamemodify(here, ':p:h:h:h')
end

--- The server command: `config.cmd`, else the server bundled with the plugin.
local function server_cmd()
  if M.config.cmd then return M.config.cmd end
  local server = vim.fs.normalize(plugin_root() .. '/server/megh-language-server.js')
  if vim.uv.fs_stat(server) then return { 'node', server, '--stdio' } end
  return nil, server
end

local warned = false

function M.start(bufnr)
  local cmd, missing = server_cmd()
  if cmd and cmd[1] == 'node' and vim.fn.executable('node') == 0 then
    cmd, missing = nil, 'node (Node.js is not on PATH)'
  end
  if not cmd then
    if not warned then
      warned = true
      vim.notify(
        ('megh: language server not found at %s. Reinstall the plugin, or set `cmd` in setup().')
          :format(missing),
        vim.log.levels.WARN
      )
    end
    return
  end
  local file = vim.api.nvim_buf_get_name(bufnr)
  local root = vim.fs.root(bufnr, { 'package.json', '.git' })
    or (file ~= '' and vim.fs.dirname(file))
    or vim.uv.cwd()
  vim.lsp.start({
    name = 'megh',
    cmd = cmd,
    root_dir = root,
    init_options = { megh = M.config.settings },
    settings = { megh = M.config.settings },
  }, { bufnr = bufnr })
end

local function client_for(bufnr)
  return vim.lsp.get_clients({ bufnr = bufnr, name = 'megh' })[1]
end

-- Neovim 0.11 made client methods use `:`; 0.10 has plain functions.
local modern = vim.fn.has('nvim-0.11') == 1

local function request(client, method, params, handler, bufnr)
  if modern then return client:request(method, params, handler, bufnr) end
  return client.request(method, params, handler, bufnr)
end

local function notify(client, method, params)
  if modern then return client:notify(method, params) end
  return client.notify(method, params)
end

--- Stop the server and start it again for every open Megh buffer.
function M.restart()
  for _, client in ipairs(vim.lsp.get_clients({ name = 'megh' })) do
    if modern then client:stop() else client.stop() end
  end
  vim.defer_fn(function()
    for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'megh' then M.start(bufnr) end
    end
  end, 500)
end

-- ---- closing tags ----

local function close_tag(bufnr)
  local client = client_for(bufnr)
  if not client then return end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  local tick = vim.api.nvim_buf_get_changedtick(bufnr)
  request(client, 'megh/closeTag', params, function(err, snippet)
    if err or type(snippet) ~= 'string' then return end
    -- Only if nothing changed while the server answered.
    if not vim.api.nvim_buf_is_valid(bufnr)
      or vim.api.nvim_get_current_buf() ~= bufnr
      or vim.api.nvim_buf_get_changedtick(bufnr) ~= tick
      or not vim.api.nvim_get_mode().mode:match('^i')
    then
      return
    end
    vim.snippet.expand(snippet)
  end, bufnr)
end

local function attach_auto_close(bufnr)
  local group = vim.api.nvim_create_augroup('megh_close_tag_' .. bufnr, { clear = true })
  local typed
  vim.api.nvim_create_autocmd('InsertCharPre', {
    group = group,
    buffer = bufnr,
    callback = function() typed = vim.v.char end,
  })
  vim.api.nvim_create_autocmd('TextChangedI', {
    group = group,
    buffer = bufnr,
    callback = function()
      local char = typed
      typed = nil
      if M.config.auto_close_tags and (char == '>' or char == '/') then close_tag(bufnr) end
    end,
  })
end

-- ---- setup ----

--- `*.megh.html` files are Megh templates, not plain HTML.
function M.filetype()
  vim.filetype.add({ pattern = { ['.*%.megh%.html'] = 'megh' } })
end

function M.setup(opts)
  M.config = vim.tbl_deep_extend('force', vim.deepcopy(defaults), opts or {})
  -- Also done by plugin/megh.lua; repeated here for setup() called before plugins load.
  M.filetype()
  local group = vim.api.nvim_create_augroup('megh', { clear = true })

  vim.api.nvim_create_autocmd('FileType', {
    group = group,
    pattern = 'megh',
    callback = function(args)
      M.start(args.buf)
      attach_auto_close(args.buf)
    end,
  })

  -- View data comes from app code (`view('name', { ... })`), so re-read the
  -- project when it is saved. Clients with file watching do this already;
  -- telling the server twice is harmless.
  vim.api.nvim_create_autocmd('BufWritePost', {
    group = group,
    pattern = { '*.ts', '*.mts', '*.cts', '*.js', '*.mjs', '*.cjs' },
    callback = function(args)
      local uri = vim.uri_from_bufnr(args.buf)
      for _, client in ipairs(vim.lsp.get_clients({ name = 'megh' })) do
        notify(client, 'workspace/didChangeWatchedFiles', { changes = { { uri = uri, type = 2 } } })
      end
    end,
  })

  vim.api.nvim_create_user_command('MeghRestart', M.restart, { desc = 'Restart the Megh language server' })

  -- Buffers that were already open before setup().
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].filetype == 'megh' then
      M.start(bufnr)
      attach_auto_close(bufnr)
    end
  end
end

return M
