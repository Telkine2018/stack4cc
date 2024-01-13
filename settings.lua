local commons = require("scripts.commons")

local settings = {
  {
    type = "bool-setting",
    name = commons.prefix .. "-use_combinators",
    setting_type = "startup",
    default_value = true,
    order = "ab"
  },
  {
    setting_type = "runtime-global",
    name = commons.prefix .. "-update-delay",
    type = "int-setting",
    default_value = 20,
    maximum_value = 600,
    minimum_value = 0,
    order = "z"
  }
}

data:extend(settings)