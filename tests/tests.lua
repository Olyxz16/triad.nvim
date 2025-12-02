local harness = require("plenary.test_harness")

print("==================================")
print("    Starting Triad.nvim Tests     ")
print("==================================")

-- Run the tests
-- The directory is "tests/"
-- The init file is "tests/minimal_init.lua"
harness.test_directory("tests/", {
  minimal_init = "tests/minimal_init.lua",
  sequential = true, -- Run one by one (easier to read output)
})
