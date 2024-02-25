local commons = require("scripts.commons")
local tools = require("scripts.tools")
local builder = require("scripts.builder")


local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip


--[[
local function on_build(e)

    local entity = e.entity or e.created_entity
    if not entity or not entity.valid then return end

    local cb = entity.get_or_create_control_behavior()
    local count = settings.global[commons.prefix .. "-value"].value
    local signals = { { signal = { type = "item", name = "iron-ore" }, count = count, index = 1 } }
    cb.parameters = signals

end

local filter = { { filter = 'name', name = commons.name } }

script.on_event(defines.events.on_built_entity, on_build, filter)
script.on_event(defines.events.on_robot_built_entity, on_build, filter)
script.on_event(defines.events.script_raised_built, on_build, filter)
script.on_event(defines.events.script_raised_revive, on_build, filter)
--]]

local combinators

local operation_map = {
    ["*"] = 1,      -- multiply by stack size
    ["/"] = 2,      -- divide by stack size, round to upper bound
    ["AND"] = 3,    -- round to nearest stack
    ["OR"] = 4,     -- round to nearest upper stack
    ["XOR"] = 5,    -- round to nearest lower stack
    ["+"] = 6,      -- divide by stack size, round to lower bound
    
}

local use_combinators = settings.startup[commons.prefix .. "-use_combinators"].value

local function register_combinator()

    local driver = {

        name = "stack-combinator",

        packed_names = { commons.cc_name, commons.ac_name, commons.dc_name },

        interface_name = commons.prefix
    }

    remote.call("compaktcircuit", "add_combinator", driver)

    remote.add_interface(commons.prefix,
        {
            get_info = function(entity)
                local cb = entity.get_or_create_control_behavior()
                local parameters = cb.parameters
                local info = {
                    operation = parameters.operation
                }
                if parameters.first_signal then
                    info.first_signal = parameters.first_signal.name
                end
                return info
            end,

            create_packed_entity = function(info, surface, position, force)

                local proc = surface.create_entity { name = commons.ac_name, force = force, position = position,
                    direction = info.direction }
                local cb = proc.get_or_create_control_behavior()
                local parameters = cb.parameters
                local first_signal = info.first_signal
                if info.first_signal then
                    parameters.first_signal = { type = "virtual", name = first_signal }
                end
                parameters.operation = info.operation
                cb.parameters = parameters
                proc.active = false

                local output = surface.create_entity { name = commons.cc_name, force = force, position = position }
                proc.connect_neighbour({
                    wire = defines.wire_type.red,
                    target_entity = output,
                    source_circuit_id = defines.circuit_connector_id.combinator_output,
                    target_circuit_id = defines.circuit_connector_id.constant_combinator
                })
                proc.connect_neighbour({
                    wire = defines.wire_type.green,
                    target_entity = output,
                    source_circuit_id = defines.circuit_connector_id.combinator_output,
                    target_circuit_id = defines.circuit_connector_id.constant_combinator
                })

                local config = {
                    proc = proc,
                    output = output,
                    invert_red = first_signal == "signal-red" or first_signal == "signal-yellow",
                    invert_green = first_signal == "signal-green" or first_signal == "signal-yellow",
                    operation = operation_map[info.operation],
                    id = proc.unit_number
                }
                config.use_combinators = use_combinators
                if config.use_combinators then
                    builder.init_combinator(config)
                end
                combinators[config.id] = config
                global.count = global.count + 1
                return proc
            end,

            create_entity = function(info, surface, force)
                local entity = surface.create_entity { name = "stack-combinator",
                    force = force,
                    position = info.position,
                    direction = info.direction }
                local cb = entity.get_or_create_control_behavior()
                local parameters = cb.parameters
                if info.first_signal then
                    parameters.first_signal = { type = "virtual", name = info.first_signal }
                end
                parameters.operation = info.operation
                cb.parameters = parameters
                script.raise_script_built { entity = entity }
                return entity
            end

        })
end

local function get_func(config, multiplier)

    local op = config.operation
    local f1
    if (op == 1) then
        return function(value, stack) return value * stack * multiplier end
    elseif (op == 2) then
        return function(value, stack) return math.ceil(value / stack * multiplier) end
    elseif (op == 3) then
        return function(value, stack)
            local op = math.abs(value) >= stack / 2 and 4 or 5
            if (op == 4 and value >= 0) or (op == 5 and value < 0) then
                return math.ceil(value / stack) * stack * multiplier
            else
                return math.floor(value / stack) * stack * multiplier
            end
        end
    elseif op == 4 then
        return function(value, stack)
            if (value > 0) then
                return math.ceil(value / stack) * stack * multiplier
            else
                return math.floor(value / stack) * stack * multiplier
            end
        end
    elseif op == 5 then
        return function(value, stack)
            if (value > 0) then
                return math.floor(value / stack) * stack * multiplier
            else
                return math.ceil(value / stack) * stack * multiplier
            end
        end
    elseif op == 6 then
        return function(value, stack) return math.floor(value / stack * multiplier) end
    end
end

local function compute_input(inputs, f, result, index)

    if not inputs or not inputs.signals then return index end
    for _, entry in ipairs(inputs.signals) do
        local signal = entry.signal
        local name = signal.name
        local value = entry.count
        if signal.type == "item" then
            local stack_size = game.item_prototypes[name].stack_size
            value = f(value, stack_size)
        end
        local r = result[name]
        if (r) then
            value = r.count + value
            r.count = value
        else
            local r = { signal = entry.signal, count = value, index = index }
            result[name] = r
            index = index + 1
        end
        if (value > 2147483647) then
            r.count = 2147483647
        elseif (value < -2147483647) then
            r.count = -2147483647
        end
    end
    return index

end

local signal_count = settings.startup["stack-combinator-signal-capacity"].value + 1

local function compute(config)

    local red_input = config.proc.get_circuit_network(defines.wire_type.red,
        defines.circuit_connector_id.combinator_input)

    local green_input = config.proc.get_circuit_network(defines.wire_type.green,
        defines.circuit_connector_id.combinator_input)

    if not config.f_red then
        config.f_red = get_func(config, config.invert_red and -1 or 1)
    end
    if not config.f_green then
        config.f_green = get_func(config, config.invert_green and -1 or 1)
    end

    local result = {}
    local index = compute_input(red_input, config.f_red, result, 1)
    index = compute_input(green_input, config.f_green, result, index)
    if index <= signal_count then
        config.output.get_or_create_control_behavior().parameters = result
    end
end

script.on_event(defines.events.on_tick, function()

    if global.count == 0 then return end

    local full_delay
    
    if not use_combinators then
        full_delay= settings.global["stack-combinator-update-delay"].value + 1
    else
        full_delay = settings.global["stack4cc-update-delay"].value + 1
    end
    local count_per_tick = math.ceil(global.count / full_delay)
    local count = 0
    local current_id = global.current_id
    local toremove
    while count < count_per_tick do
        local config
        current_id, config = next(combinators, current_id)
        if not config then
            break
        end
        if not config.proc.valid or not config.output.valid then
            if not toremove then toremove = {} end
            table.insert(toremove, config)
        elseif not config.use_combinators then
            compute(config)
        else
            builder.compute(config)
        end
        count = count + 1
    end
    if toremove then
        count = 0
        for _, c in ipairs(toremove) do
            if c.proc.valid then c.proc.destroy() end
            if c.output.valid then c.output.destroy() end
            combinators[c.id] = nil
            count = count + 1
            if c.id == current_id then
                current_id = nil
            end
        end
        global.count = global.count - count
    end
    global.current_id = current_id

end)

script.on_load(function()

    combinators = global.combinators
    register_combinator()
end
)
script.on_init(function()

    global.combinators = {}
    global.count = 0
    combinators = global.combinators
    register_combinator()
end
)


commands.add_command("stack4cc_clean", { "stack4cc_clean" },
    function(e)
        local count = 0
        for _, _ in pairs(global.combinators) do
            count = count + 1
        end
        tools.debug("global.count=" .. global.count .. ",count=" .. count)
        global.count = count
    end)
