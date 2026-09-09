local citations_path = assert(
  os.getenv("CITATIONS_LUA"),
  "CITATIONS_LUA must name the citations module"
)

local citeref_options
local blink_options

package.preload["citeref"] = function()
  return {
    setup = function(options)
      citeref_options = options
    end,
  }
end

package.preload["blink.cmp"] = function()
  return {
    setup = function(options)
      blink_options = options
    end,
  }
end

local citations = dofile(citations_path)

local temporary = vim.fn.tempname()
local wiki = temporary .. "/wiki"
local note = wiki .. "/topics/note.md"
local bibliography = wiki .. "/references.bib"

vim.fn.mkdir(wiki .. "/topics", "p")
vim.fn.writefile({ "@book{example," }, bibliography)

local found = citations.find_bibliography(note)
assert(#found == 1, "expected one ancestor bibliography")
assert(
  vim.fs.normalize(found[1]) == vim.fs.normalize(bibliography),
  "expected to find the wiki's references.bib"
)

vim.api.nvim_buf_set_name(0, note)
citations.setup()

assert(citeref_options.backend == "blink", "expected the Blink citeref backend")
assert(
  citeref_options.keymaps.enabled == false,
  "expected citeref's unrelated keymaps to be disabled"
)

local dynamic_bibliographies = citeref_options.bib_files()
assert(
  vim.deep_equal(dynamic_bibliographies, found),
  "expected citeref to find the bibliography from the current buffer"
)

assert(blink_options.keymap.preset == "super-tab", "expected super-tab completion")
assert(
  blink_options.sources.providers.citeref.module == "citeref.backends.blink",
  "expected the citeref Blink provider"
)
assert(
  vim.deep_equal(blink_options.sources.per_filetype.markdown, { "citeref" }),
  "expected citeref completion for Markdown"
)
assert(
  vim.deep_equal(blink_options.sources.per_filetype.pandoc, { "citeref" }),
  "expected citeref completion for Pandoc"
)

vim.fn.delete(temporary, "rf")
print("Neovim citation completion tests passed")
