local M = {}

function M.find_bibliography(buffer)
  local start = buffer ~= "" and vim.fs.dirname(buffer) or vim.fn.getcwd()

  return vim.fs.find("references.bib", {
    path = start,
    upward = true,
    type = "file",
  })
end

function M.setup()
  require("citeref").setup({
    backend = "blink",
    bib_files = function()
      return M.find_bibliography(vim.api.nvim_buf_get_name(0))
    end,
    keymaps = {
      enabled = false,
    },
  })

  require("blink.cmp").setup({
    keymap = {
      preset = "super-tab",
    },
    sources = {
      default = {},
      per_filetype = {
        markdown = { "citeref" },
        pandoc = { "citeref" },
      },
      providers = {
        citeref = {
          name = "citeref",
          module = "citeref.backends.blink",
        },
      },
    },
  })
end

return M
