Project Architecture & Feasibility Report: "Triad.nvim"

1. Executive Summary

The goal is to build a "Pure Lua" file manager for Neovim that merges three distinct philosophies:

Layout: Miller Columns (Yazi/Ranger style) - Parent, Current, Preview.

Interaction: Buffer-based filesystem editing (Oil.nvim style) in the center pane.

Context: Git status integration (Neo-tree style).

2. Technical Stack & Dependencies

Core Requirements

Language: Lua 5.1 (LuaJIT as embedded in Neovim).

Neovim Version: 0.9.0+ (Required for stable vim.fs and vim.uv APIs).

Libraries

plenary.nvim (Highly Recommended):

Why: It provides the plenary.scandir for fast directory scanning and plenary.path for robust path manipulation. It also handles async jobs (essential for Git integration without freezing the UI).

nvim-web-devicons (Standard):

Why: To render file icons. This is the community standard.

"Pure Lua" Constraint

To adhere to the "Pure Lua" requirement (avoiding uberzug or Rust binaries), we will rely entirely on vim.uv (formerly vim.loop) for filesystem operations. This ensures portability and speed without external compilation.

3. Architecture Design

We should adopt a Model-View-Controller (MVC) approach to manage the complexity of syncing three windows and an editable buffer.

A. The View (UI Layer)

The UI consists of three floating windows (or splits) arranged horizontally.

Left (Parent): Read-only buffer. Shows the list of the parent directory.

Center (Current): buftype=acwrite. This is the "Oil" component. It looks like a list, but acts like a text buffer.

Right (Preview): Read-only. Displays either the contents of a file (syntax highlighted) or a directory listing of the child.

Challenge: Synchronization. Moving the cursor in the Center pane must immediately update the Right pane and highlight the parent directory in the Left pane.

B. The Model (State & FS)

This layer handles the "Oil-like" functionality.

Parsing: When the user writes (:w) the Center buffer, the plugin must parse the text lines.

Diffing: Compare the current buffer state against the initial filesystem state.

Execution:

Rename: If a line text changed.

Delete: If a line is removed.

Move: If a line is pasted from another directory (complex, potentially V2 feature).

Create: If a new line is added.

C. The Controller (Logic & Git)

Navigation: Handling h/j/k/l to move between hierarchy levels.

Git Integration: A background job runs git status --porcelain -u relative to the current root. The results are parsed and applied as extmarks (highlights/icons) to the filenames in the Center and Left panes.

4. Implementation Details: The "Oil" Mechanism

This is the most critical technical component.

Rendering: Iterate the directory using vim.uv.fs_scandir. Print names to the buffer.

Metadata Storage: Store the original ID/Path of the file in a Lua table keyed by the line number of the original render.

The Save Hook:

vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = center_buf_id,
    callback = function()
        -- 1. Parse current buffer lines
        -- 2. Compare with original state
        -- 3. Execute fs.rename / fs.unlink / fs.mkdir
        -- 4. Reload buffer
    end
})


5. Testing Strategy

Framework: busted (via plenary.test_harness).

Unit Tests: Test path manipulation and the Git status parser.

Integration Tests:

Create a temporary directory structure.

Open the plugin.

Simulate text edits in the buffer.

Trigger save.

Assert filesystem changes.

6. Risk Assessment

Performance: Loading the "Right" pane (preview) on every cursor move can induce lag.

Mitigation: Implement debouncing (wait 50-100ms after cursor stops before rendering preview) and cache previews for small files.

Large Directories: Rendering 10,000 files in the Center pane as editable text is fast in Neovim, but calculating Git status for them might be slow.

Mitigation: Async jobs for Git; lazy loading for directory scanning if necessary.
