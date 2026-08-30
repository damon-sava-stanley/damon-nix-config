local roll_path = assert(os.getenv("ROLL_LUA"), "ROLL_LUA must name the Roll module")

local die_results = { 3, 4 }
local random_calls = {}

dofile(roll_path).setup({
  random = function(maximum)
    table.insert(random_calls, maximum)
    return assert(table.remove(die_results, 1), "unexpected extra die roll")
  end,
})

vim.cmd("Roll 2d6")

assert(#random_calls == 2, "expected two dice to be rolled")
assert(random_calls[1] == 6 and random_calls[2] == 6, "expected two six-sided dice")
assert(vim.fn.getreg('"') == "7", "expected the unnamed register to contain 7")

local messages = vim.api.nvim_exec2("messages", { output = true }).output
assert(messages:find("2d6 = 7", 1, true), "expected the roll total in Neovim messages")

for _, notation in ipairs({
  "0d6",
  "2d0",
  "2D6",
  "2d6+0",
  "2d6-0",
  "10000d6+",
  "9999d6+2",
  "dice",
  "10001d6",
  "2d1000001",
}) do
  vim.fn.setreg('"', "unchanged")
  pcall(vim.cmd, "Roll " .. notation)
  assert(
    vim.fn.getreg('"') == "unchanged",
    "invalid notation replaced the unnamed register: " .. notation
  )
end

messages = vim.api.nvim_exec2("messages", { output = true }).output
assert(
  messages:find("Roll expects <positive integer>d<positive integer>", 1, true),
  "expected a validation message for malformed notation"
)

die_results = { 1, 5, 3 }
random_calls = {}
vim.cmd("Roll 2d6+")

assert(#random_calls == 3, "expected advantage to roll one extra die")
assert(vim.fn.getreg('"') == "8", "expected advantage to discard the lowest roll")

messages = vim.api.nvim_exec2("messages", { output = true }).output
assert(messages:find("2d6+ = 8", 1, true), "expected the advantage total in Neovim messages")

die_results = { 6, 2, 4, 1 }
random_calls = {}
vim.cmd("Roll 2d6+2")

assert(#random_calls == 4, "expected explicit advantage to roll two extra dice")
assert(vim.fn.getreg('"') == "10", "expected advantage to discard the two lowest rolls")

die_results = { 6, 2, 4 }
random_calls = {}
vim.cmd("Roll 2d6-")

assert(#random_calls == 3, "expected disadvantage to roll one extra die")
assert(vim.fn.getreg('"') == "6", "expected disadvantage to discard the highest roll")

messages = vim.api.nvim_exec2("messages", { output = true }).output
assert(messages:find("2d6- = 6", 1, true), "expected the disadvantage total in Neovim messages")

die_results = { 6, 2, 4, 1 }
random_calls = {}
vim.cmd("Roll 2d6-2")

assert(#random_calls == 4, "expected explicit disadvantage to roll two extra dice")
assert(vim.fn.getreg('"') == "3", "expected disadvantage to discard the two highest rolls")

print("Neovim Roll command tests passed")
