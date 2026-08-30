local M = {}

local MAX_DICE = 10000
local MAX_SIDES = 1000000
local INVALID_NOTATION =
  "Roll expects <positive integer>d<positive integer>, optionally followed by + or - and an optional positive integer (default 1; up to 10000 rolls and 1000000 sides)"

local function parse_notation(notation)
  local count_text, sides_text = notation:match("^(%d+)d(%d+)$")
  local modifier, modifier_text
  if not count_text then
    count_text, sides_text, modifier, modifier_text =
      notation:match("^(%d+)d(%d+)([+-])(%d*)$")
  end

  local count = tonumber(count_text)
  local sides = tonumber(sides_text)
  local extra_dice = 0
  if modifier then
    extra_dice = modifier_text == "" and 1 or tonumber(modifier_text)
  end

  if
    not count
    or not sides
    or not extra_dice
    or count < 1
    or sides < 1
    or (modifier and extra_dice < 1)
    or count + extra_dice > MAX_DICE
    or sides > MAX_SIDES
  then
    return nil
  end

  return count, sides, modifier, extra_dice
end

function M.setup(options)
  options = options or {}
  local random = options.random or math.random

  vim.api.nvim_create_user_command("Roll", function(command)
    local count, sides, modifier, extra_dice = parse_notation(command.args)
    if not count then
      vim.notify(INVALID_NOTATION, vim.log.levels.ERROR)
      return
    end

    local rolls = {}
    local roll_count = count + extra_dice
    for _ = 1, roll_count do
      local roll = random(sides)
      table.insert(rolls, roll)
    end

    if modifier then
      table.sort(rolls)
    end

    local first_kept = modifier == "+" and extra_dice + 1 or 1
    local last_kept = modifier == "-" and count or roll_count
    local total = 0
    for index = first_kept, last_kept do
      total = total + rolls[index]
    end

    vim.fn.setreg('"', tostring(total))
    vim.api.nvim_echo({ { string.format("%s = %d", command.args, total) } }, true, {})
  end, {
    nargs = 1,
    desc = "Roll dice and copy the total",
  })
end

return M
