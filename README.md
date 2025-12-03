# Triad.nvim

Like [yazi](https://github.com/mikavilpas/yazi.nvim), but ⚡*slower*⚡.

**Triad.nvim** is a pure-Lua, Miller-column style file explorer for Neovim. It features a three-pane layout (Parent | Current | Preview) and allows you to edit your filesystem directly by editing the buffer, similar to [oil.nvim](https://github.com/stevearc/oil.nvim).

**⚠️ UNDER HEAVY DEVELOPMENT. THINGS MAY BREAK. USE AT YOUR OWN RISK.**

## Features

*   **Miller Columns:** Navigate with a Parent, Current, and Preview pane.
*   **Buffer-Based Editing:** Rename, create, and delete files by simply editing the file list buffer.
*   **Git Integration:** Async git status updates.
*   **Icons:** Integration with `nvim-web-devicons`.
*   **Zero Binaries:** Pure Lua implementation.

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
    "Olyxz16/triad.nvim",
    dependencies = {
        "nvim-lua/plenary.nvim",
        "nvim-tree/nvim-web-devicons", -- Optional, for icons
    },
    config = function()
        require("triad").setup({
            -- Optional configuration
            -- devicons_enabled = true,
            -- show_hidden = false,
        })
    end,
    cmd = "Triad",
}
```

## Usage

Open the file explorer with the command:

```vim
:Triad
```

### Navigation Mode (Default)

When you open Triad, you start in **Navigation Mode**. The buffer is read-only.

| Key | Action |
| :--- | :--- |
| `j` / `k` | Move cursor up/down |
| `h` / `-` | Go to parent directory |
| `l` | Enter directory under cursor |
| `<CR>` | Enter directory OR Open file |
| `q` | Close Triad |
| `e` | Enter **Edit Mode** |
| `i` | Enter **Edit Mode** (insert at cursor) |
| `a` | Enter **Edit Mode** (append after cursor) |
| `I` | Enter **Edit Mode** (insert at start of line) |
| `A` | Enter **Edit Mode** (append at end of line) |

### Edit Mode

Press `e` (or `i`, `a`, etc.) to enter **Edit Mode**. The buffer becomes modifiable. You can use standard Vim motions and text editing commands.

*   **Rename:** Edit the filename on the line.
*   **Delete:** Delete the line (e.g., `dd`).
*   **Create:** Add a new line with the desired filename.
    *   Ending with `/` creates a directory (e.g., `new_folder/`).
    *   Otherwise, it creates a file (e.g., `new_file.lua`).

**Applying Changes:**

1.  Press `<Esc>` to return to Normal mode.
2.  Triad will prompt you to confirm the changes (Create, Rename, Delete).
3.  Select `Yes` to apply or `No` to discard.

## Configuration

```lua
require("triad").setup({
  layout = {
    parent_width = 20,
    current_width = 35,
    preview_width = 45,
  },
  git_icons = {
    added = '',
    modified = '',
    deleted = '',
    untracked = '',
    ignored = '',
    renamed = '➜',
    conflict = '',
  },
  devicons_enabled = true,
  show_hidden = false,
})
```
