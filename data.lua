
local commons = require("scripts.commons")

local boxsize = commons.boxsize
local prefix = commons.prefix
local function png(name) return ('__' .. prefix .. '__/graphics/%s.png'):format(name) end
local function merge_table(dst, sources)
	for _, src in pairs(sources) do
		for name, value in pairs(src) do
			dst[name] = value
		end
	end
	return dst
end


local invisible_sprite = { filename = png('invisible'), width = 1, height = 1 }
local wire_conn = { wire = { red = { 0, 0 }, green = { 0, 0 } }, shadow = { red = { 0, 0 }, green = { 0, 0 } } }

local signal_count = settings.startup["stack-combinator-signal-capacity"].value

local commons_attr = {
    flags = { 'placeable-off-grid' , "hidden", "hide-alt-info", "not-on-map", "not-upgradable", "not-deconstructable", "not-blueprintable" },
    collision_mask = {},
    minable = nil,
    selectable_in_game = false,
    circuit_wire_max_distance = 64,
    sprites = invisible_sprite,
    activity_led_sprites = invisible_sprite,
    activity_led_light_offsets = { { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 } },
    circuit_wire_connection_points = { wire_conn, wire_conn, wire_conn, wire_conn },
    draw_circuit_wires = false,
    collision_box = { { -boxsize, -boxsize }, { boxsize, boxsize } },
    selection_box = { { -0.01, -0.01 }, { 0.01, 0.01 } },
    created_smoke = nil,
    item_slot_count = signal_count
}


local cc = table.deepcopy(table.deepcopy(data.raw['constant-combinator']['constant-combinator']))
merge_table(cc,
     {  commons_attr,
        { name = commons.cc_name}
})

local ac = table.deepcopy(data.raw["arithmetic-combinator"]["arithmetic-combinator"])
merge_table(ac, {

    commons_attr,
    {
        name = commons.ac_name,
        and_symbol_sprites = invisible_sprite,
        divide_symbol_sprites = invisible_sprite,
        left_shift_symbol_sprites = invisible_sprite,
        minus_symbol_sprites = invisible_sprite,
        plus_symbol_sprites = invisible_sprite,
        power_symbol_sprites = invisible_sprite,
        multiply_symbol_sprites = invisible_sprite,
        or_symbol_sprites = invisible_sprite,
        right_shift_symbol_sprites = invisible_sprite,
        xor_symbol_sprites = invisible_sprite,
        modulo_symbol_sprites = invisible_sprite
    }
})

local dc = table.deepcopy(data.raw["decider-combinator"]["decider-combinator"])
merge_table(dc, {

    commons_attr,
    {
        name = commons.dc_name,
		equal_symbol_sprites = invisible_sprite,
		greater_or_equal_symbol_sprites = invisible_sprite,
		greater_symbol_sprites = invisible_sprite,
		less_or_equal_symbol_sprites = invisible_sprite,
		less_symbol_sprites = invisible_sprite,
		not_equal_symbol_sprites = invisible_sprite
    }
})


data:extend { cc, ac, dc }
