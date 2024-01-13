local commons = require("scripts.commons")
local tools = require("scripts.tools")

local builder = {}

local debug = tools.debug
local cdebug = tools.cdebug
local get_vars = tools.get_vars
local strip = tools.strip

local boxsize = commons.boxsize

----------------------------------------------------------------------------

local red = defines.wire_type.red
local green = defines.wire_type.green
local combinator_output = defines.circuit_connector_id.combinator_output
local combinator_input = defines.circuit_connector_id.combinator_input

function builder.create_combi(config, name)
    local proc = config.proc
    local index_pos = config.index_pos or 0
    index_pos = index_pos + 1
    config.index_pos = index_pos + 1
    local indexx = index_pos % 20
    local indexy = index_pos / 20
    return proc.surface.create_entity { name = name, force = proc.force, 
        position = { proc.position.x + boxsize * indexx * 3, proc.position.y + boxsize * indexy * 3  } }
end

function builder.create_cc(config)
    return builder.create_combi(config, commons.cc_name)
end

function builder.create_ac(config, p1, operation, p2, output_signal)
    local ac = builder.create_combi(config, commons.ac_name)
    local cb = ac.get_or_create_control_behavior()
    local p = cb.parameters
    if type(p1) == "number" then
        p.first_signal = nil
        p.first_constant = p1
    else
        p.first_signal = p1
    end
    p.operation = operation
    if type(p2) == "number" then
        p.second_signal = nil
        p.second_constant = p2
    else
        p.second_signal = p2
    end
    p.output_signal = output_signal
    cb.parameters = p
    return ac
end

function builder.create_dc(config, p1, comparator, p2, output_signal, copy_count_from_input)

    local dc = builder.create_combi(config, commons.dc_name)
    local cb = dc.get_or_create_control_behavior()
    local p = cb.parameters
    p.first_signal = p1
    p.comparator = comparator
    if type(p2) == "number" then
        p.second_signal = nil
        p.constant = p2
    else
        p.second_signal = p2
    end
    p.output_signal = output_signal
    p.copy_count_from_input = copy_count_from_input
    cb.parameters = p
    return dc
end

local minus_500m = -500000000
local minus_1G = -1000000000
local plus_1G = 1000000000

local signal_command = { type = "item", name = "deconstruction-planner" }
local signal_each = { type = "virtual", name = "signal-each" }
local signal_everything = { type = "virtual", name = "signal-everything" }

function builder.create_signal_chain(config)

    local process_chain = {}
    local c1            = builder.create_ac(config, signal_each, "*", 1, signal_each)

    local filter1 = builder.create_cc(config)
    c1.connect_neighbour { source_circuit_id = combinator_output, target_entity = filter1, wire = red }

    local c2 = builder.create_dc(config, signal_each, "<", minus_500m, signal_each, true)
    filter1.connect_neighbour { target_entity = c2, target_circuit_id = combinator_input, wire = red }

    local filter2 = builder.create_cc(config)
    c2.connect_neighbour { source_circuit_id = combinator_output, target_entity = filter2, wire = red }

    local c3 = builder.create_ac(config, signal_each, "*", 1, signal_each)
    filter2.connect_neighbour { target_circuit_id = combinator_input, target_entity = c3, wire = red }

    if (config.sensor) then
        filter1.connect_neighbour { target_entity = config.sensor.filter_input, target_circuit_id = combinator_input,
            wire = green }
    end

    process_chain.input = c1
    process_chain.filter1 = filter1
    process_chain.filter2 = filter2
    process_chain.output = c3

    config.signal_chain = process_chain
    return process_chain
end

function builder.create_stack_chain(config, stack)

    local process_chain = {}
    local c1            = builder.create_ac(config, signal_each, "*", 1, signal_each)
    local filter1       = builder.create_cc(config)
    local c2            = builder.create_dc(config, signal_each, "<", minus_500m, signal_each, true)
    local filter2       = builder.create_cc(config)

    c1.connect_neighbour { source_circuit_id = combinator_output, target_entity = filter1, wire = red }
    filter1.connect_neighbour { target_entity = c2, target_circuit_id = combinator_input, wire = red }
    c2.connect_neighbour { source_circuit_id = combinator_output, target_entity = filter2, wire = red }

    process_chain.input = c1
    process_chain.filter1 = filter1
    process_chain.filter2 = filter2

    if (config.sensor) then
        filter1.connect_neighbour { target_entity = config.sensor.filter_input, target_circuit_id = combinator_input,
            wire = green }
    end

    local c3
    if config.operation == 1 then
        c3 = builder.create_ac(config, signal_each, "*", stack, signal_each)
        process_chain.output = c3
    elseif config.operation == 2 then
        c3 = builder.create_ac(config, signal_each, "/", stack, signal_each)
        process_chain.output = c3

    elseif config.operation == 3 then

        local test1 = builder.create_dc(config, signal_each, ">=", stack / 2, signal_each, true)

        local cc1 = builder.create_cc(config)
        test1.connect_neighbour { target_entity = cc1, source_circuit_id = combinator_output, wire = red }

        local div1 = builder.create_ac(config, signal_each, "/", stack, signal_each)
        cc1.connect_neighbour { target_entity = div1, target_circuit_id = combinator_input, wire = red }

        local test2 = builder.create_dc(config, signal_each, "<=", -stack / 2, signal_each, true)
        test1.connect_neighbour { source_circuit_id = combinator_input, target_entity = test2,
            target_circuit_id = combinator_input, wire = red }

        local cc2 = builder.create_cc(config)
        test2.connect_neighbour { target_entity = cc2, source_circuit_id = combinator_output, wire = red }

        local div2 = builder.create_ac(config, signal_each, "/", stack, signal_each)
        cc2.connect_neighbour { target_entity = div2, target_circuit_id = combinator_input, wire = red }

        local mul1 = builder.create_ac(config, signal_each, "*", stack, signal_each)
        div1.connect_neighbour { source_circuit_id = combinator_output, target_entity = mul1,
            target_circuit_id = combinator_input, wire = red }
        div2.connect_neighbour { source_circuit_id = combinator_output, target_entity = mul1,
            target_circuit_id = combinator_input, wire = red }

        process_chain.op_filter1 = cc1
        process_chain.op_filter2 = cc2
        process_chain.op_filter_base = stack - 1
        process_chain.output = mul1

        c3 = test1
    elseif config.operation == 5 then

        local div1 = builder.create_ac(config, signal_each, "/", stack, signal_each)

        local mul1 = builder.create_ac(config, signal_each, "*", stack, signal_each)
        div1.connect_neighbour { source_circuit_id = combinator_output, target_entity = mul1,
            target_circuit_id = combinator_input, wire = red }

        c3 = div1
        process_chain.output = mul1
    elseif config.operation == 4 then

        local test1 = builder.create_dc(config, signal_each, ">=", 0, signal_each, true)

        local cc1 = builder.create_cc(config)
        test1.connect_neighbour { target_entity = cc1, source_circuit_id = combinator_output, wire = red }

        local div1 = builder.create_ac(config, signal_each, "/", stack, signal_each)
        cc1.connect_neighbour { target_entity = div1, target_circuit_id = combinator_input, wire = red }

        local test2 = builder.create_dc(config, signal_each, "<=", 0, signal_each, true)
        test1.connect_neighbour { source_circuit_id = combinator_input, target_entity = test2,
            target_circuit_id = combinator_input, wire = red }

        local cc2 = builder.create_cc(config)
        test2.connect_neighbour { target_entity = cc2, source_circuit_id = combinator_output, wire = red }

        local div2 = builder.create_ac(config, signal_each, "/", stack, signal_each)
        cc2.connect_neighbour { target_entity = div2, target_circuit_id = combinator_input, wire = red }

        local mul1 = builder.create_ac(config, signal_each, "*", stack, signal_each)
        div1.connect_neighbour { source_circuit_id = combinator_output, target_entity = mul1,
            target_circuit_id = combinator_input, wire = red }
        div2.connect_neighbour { source_circuit_id = combinator_output, target_entity = mul1,
            target_circuit_id = combinator_input, wire = red }

        process_chain.op_filter1 = cc1
        process_chain.op_filter2 = cc2
        process_chain.op_filter_base = stack - 1
        process_chain.output = mul1
        c3 = test1
    end

    filter2.connect_neighbour {
        wire = red,
        target_entity = c3,
        target_circuit_id = combinator_input
    }

    return process_chain
end

function builder.create_sensor(config)

    local sensor  = {}
    local c1      = builder.create_ac(config, signal_each, "*", 1, signal_each)
    local c2      = builder.create_dc(config, signal_each, ">", minus_500m,
        signal_each, false)
    local c3      = builder.create_dc(config, signal_command, "=", 0,
        signal_everything, true)
    local command = builder.create_cc(config)

    local cb = command.get_or_create_control_behavior()
    cb.parameters = { { signal = signal_command, count = 1, index = 1 } }
    cb.enabled = false

    c1.connect_neighbour { source_circuit_id = combinator_output, target_entity = c2,
        target_circuit_id = combinator_input, wire = red }
    c2.connect_neighbour { source_circuit_id = combinator_output, target_entity = c3,
        target_circuit_id = combinator_input, wire = red }
    c3.connect_neighbour { source_circuit_id = combinator_output, target_entity = c3,
        target_circuit_id = combinator_input, wire = red }
    command.connect_neighbour { target_entity = c3, target_circuit_id = combinator_input, wire = green }

    sensor.input = c1
    sensor.filter_input = c2
    sensor.output = c3
    sensor.command = command

    sensor.input.connect_neighbour { source_circuit_id = combinator_input, target_entity = config.proc,
        target_circuit_id = combinator_input, wire = red }
    sensor.input.connect_neighbour { source_circuit_id = combinator_input, target_entity = config.proc,
        target_circuit_id = combinator_input, wire = green }

    config.sensor = sensor
    return sensor
end

function builder.set_cc(cc, item, value)
    local cb = cc.get_or_create_control_behavior()
    cb.set_signal(1, { signal = { type = "item", name = item }, count = value })
end

function builder.add_item(process_chain, signal)
    local cb = process_chain.filter1.get_or_create_control_behavior()
    local parameters = cb.parameters
    local count = cb.signals_count
    local index
    for i = 1, count do
        local name = parameters[i].signal.name
        if not name then
            index = i
            break
        elseif name == signal.name and parameters[i].signal.type == signal.type then
            return false
        end
    end
    if not index then return false end
    cb.set_signal(index, { signal = signal, count = minus_1G })

    cb = process_chain.filter2.get_or_create_control_behavior()
    cb.set_signal(index, { signal = signal, count = plus_1G })

    if process_chain.op_filter1 then
        cb = process_chain.op_filter1.get_or_create_control_behavior()
        cb.set_signal(index, { signal = signal, count = process_chain.op_filter_base })
        cb = process_chain.op_filter2.get_or_create_control_behavior()
        cb.set_signal(index, { signal = signal, count = -process_chain.op_filter_base })
    end
    return true
end

function builder.connect_input_output(config, chain, direct)

    if direct or not config.combi_input then
        chain.input.connect_neighbour { source_circuit_id = combinator_input, target_entity = config.proc, target_circuit_id = combinator_input, wire = red   }
        chain.input.connect_neighbour { source_circuit_id = combinator_input, target_entity = config.proc, target_circuit_id = combinator_input, wire = green   }
    else
        chain.input.connect_neighbour { source_circuit_id = combinator_input, target_entity = config.combi_input, target_circuit_id = combinator_output, wire = red   }
        chain.input.connect_neighbour { source_circuit_id = combinator_input, target_entity = config.combi_input, target_circuit_id = combinator_output, wire = red  }
    end
    chain.output.connect_neighbour { source_circuit_id = combinator_output, target_entity = config.proc, target_circuit_id = combinator_output, wire = red }
    chain.output.connect_neighbour { source_circuit_id = combinator_output, target_entity = config.proc, target_circuit_id = combinator_output, wire = green }
end

function builder.init_combinator(config)

    config.stack_map = {}
    builder.create_sensor(config)

    if config.invert_red or config.invert_green then

        local c1 = builder.create_ac(config, signal_each, "*", config.invert_red and -1 or 1, signal_each)
        local c2 = builder.create_ac(config, signal_each, "*", config.invert_green and -1 or 1, signal_each)

        c1.connect_neighbour{source_circuit_id=combinator_input, target_entity=config.proc,  target_circuit_id=combinator_input, wire=red}
        c2.connect_neighbour{source_circuit_id=combinator_input, target_entity=config.proc,  target_circuit_id=combinator_input, wire=green}
        c2.connect_neighbour{source_circuit_id=combinator_output, target_entity=c1,  target_circuit_id=combinator_output, wire=red}
        config.combi_input = c1
    end
end

function builder.compute(config)

    local sensor = config.sensor
    local circuit = sensor.output.get_circuit_network(red, combinator_output)
    local signals = circuit.signals
    if not signals or #signals == 0 then

        config.sensor.command.get_or_create_control_behavior().enabled = false
        return
    end
    for _, signal in ipairs(signals) do
        local ssignal = signal.signal
        if ssignal.type == "item" then
            local stack = game.item_prototypes[ssignal.name].stack_size
            local chain = config.stack_map[stack]
            if not chain then
                chain = builder.create_stack_chain(config, stack)
                builder.connect_input_output(config, chain)
                config.stack_map[stack] = chain
            end
            builder.add_item(chain, ssignal)
        else
            local chain = config.signal_chain
            if not chain then
                chain = builder.create_signal_chain(config)
                builder.connect_input_output(config, chain, true)
            end
            builder.add_item(chain, ssignal) 
        end
    end
    config.sensor.command.get_or_create_control_behavior().enabled = true

end

return builder
