local fn = vim.fn
local api = vim.api

local M = {}
local NS = api.nvim_create_namespace('jump')
local CR = api.nvim_replace_termcodes('<Cr>', true, true, true)
local BS = api.nvim_replace_termcodes('<Bs>', true, true, true)
local ESC = api.nvim_replace_termcodes('<Esc>', true, true, true)
local LABELS = {}
local CONFIG = {
  -- The labels that may be used, in order of their preference.
  labels = 'fdsaghjklrewqtyuiopvcxzbnm',

  -- The highlight group to use for match highlights.
  search = 'FlashMatch',

  -- The highlight group to use for labels.
  label = 'FlashLabel',

  -- The highlight group to use for the first (CR) label.
  first_search = 'FlashCurrent',

  -- The highlight group to use for the backdrop.
  backdrop = 'FlashBackdrop',
}

local function search(pattern, lines, start_line, matches)
  local lower = pattern == pattern:lower()

  for idx, line in ipairs(lines) do
    local lnum = start_line + idx - 1
    local line = lower and line:lower() or line

    if #line > 0 then
      local col = 1

      while true do
        local start, stop = line:find(pattern, col, true)

        if not start then
          break
        end

        col = stop + 1
        table.insert(matches, {
          line = lnum - 1,
          start_col = start - 1,
          end_col = stop,
          line_index = idx,
        })
      end
    end
  end
end

local function backdrop(buf, top, bot)
  for line = top, bot do
    api.nvim_buf_set_extmark(buf, NS, line - 1, 0, {
      hl_group = CONFIG.backdrop,
      end_row = line,
      hl_eol = true,
      priority = 5000,
      strict = false,
    })
  end
end

local function available_labels(lines, matches)
  local avail = {}

  for _, char in ipairs(LABELS) do
    avail[char] = true
  end

  -- Disable all the labels that conflict with any of the characters that may be
  -- matched by the next input.
  for _, match in ipairs(matches) do
    local next_col = match.end_col + 1
    local next_char = lines[match.line_index]:sub(next_col, next_col):lower()

    avail[next_char] = false
  end

  return avail
end

function M.start(opts)
  opts = opts or {}
  local before = opts.before or false
  local pending = fn.mode(1):match('^no') ~= nil
  local win = api.nvim_get_current_win()
  local buf = api.nvim_win_get_buf(win)
  local info = fn.getwininfo(win)[1]
  local top = info.topline
  local bot = info.botline
  local lines = api.nvim_buf_get_lines(buf, top - 1, bot, true)
  local chars = ''
  local matches = {}
  local active = {}

  backdrop(buf, top, bot)
  vim.cmd.redraw()

  while true do
    api.nvim_echo({ { '/' .. chars, '' } }, false, {})

    local char = fn.getcharstr(-1)
    local jump_to = active[char]

    if char == ESC then
      break
    elseif char == CR then
      for _, char in ipairs(LABELS) do
        jump_to = active[char]

        if jump_to then
          break
        end
      end

      if jump_to then
        if pending and jump_to[3] then
          vim.cmd('normal! v')
        end
        api.nvim_win_set_cursor(win, { jump_to[1], jump_to[2] })
      end

      break
    elseif char == BS then
      chars = chars:sub(1, #chars - 1)
    elseif jump_to then
      if pending and jump_to[3] then
        vim.cmd('normal! v')
      end
      api.nvim_win_set_cursor(win, { jump_to[1], jump_to[2] })
      break
    else
      chars = chars .. char
    end

    matches = {}
    active = {}
    api.nvim_buf_clear_namespace(buf, NS, 0, -1)

    if #chars > 0 then
      backdrop(buf, top, bot)

      search(chars, lines, top, matches)

      local cursor = api.nvim_win_get_cursor(win)
      local cursor_line = cursor[1] - 1
      local cursor_col = cursor[2]

      local cols = vim.go.columns
      local dfrom = cursor_line * cols + cursor_col
      table.sort(matches, function(a, b)
        local da = math.abs(a.line * cols + a.start_col - dfrom)
        local db = math.abs(b.line * cols + b.start_col - dfrom)
        return da < db
      end)

      local avail = available_labels(lines, matches)

      local is_first = true
      for _, match in ipairs(matches) do
        local label = nil

        for _, cur in ipairs(LABELS) do
          if avail[cur] then
            label = cur
            avail[cur] = false
            break
          end
        end

        local hl = is_first and CONFIG.first_search or CONFIG.search
        is_first = false
        vim.hl.range(
          buf,
          NS,
          hl,
          { match.line, match.start_col },
          { match.line, match.end_col },
          { priority = 5001 }
        )

        if label then
          local jump_col = match.start_col
          local match_pos = match.line * cols + match.start_col
          local after_cursor = match_pos >= dfrom
          local jump_line = match.line
          if before then
            if after_cursor then
              if match.start_col == 0 then
                jump_line = match.line - 1
                local prev_line = lines[match.line_index - 1]
                jump_col = prev_line and math.max(0, #prev_line - 1) or 0
              else
                jump_col = match.start_col - 1
              end
            else
              local line_len = #lines[match.line_index]
              if match.start_col + 1 >= line_len then
                jump_line = match.line + 1
                jump_col = 0
              else
                jump_col = match.start_col + 1
              end
            end
          end
          active[label] = { jump_line + 1, jump_col, after_cursor }
          api.nvim_buf_set_extmark(buf, NS, match.line, match.start_col, {
            virt_text = { { label, CONFIG.label } },
            virt_text_pos = 'overlay',
            priority = 5002,
          })
        end
      end
    end

    vim.cmd.redraw()
  end

  api.nvim_buf_clear_namespace(buf, NS, 0, -1)
  api.nvim_echo({ { '', '' } }, false, {})
  vim.cmd.redraw()
end

function M.setup(opts)
  if opts then
    CONFIG = vim.tbl_extend('force', CONFIG, opts)
  end

  LABELS = fn.split(CONFIG.labels, '\\zs')
end

M.setup()

return M
