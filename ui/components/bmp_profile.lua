-- BMP Profile UI component - displays in upper left corner
-- Independent UI module that doesn't modify existing UI elements

MP.BMP_PROFILE_UI = nil
MP.BMP_PROFILE_REF = {
	username = localize("k_profile_username"),
	ranked_mmr = "...",
	ranked_rank = "...",
	ranked_mmr_change = "...",
	smallworld_mmr = "...",
	smallworld_rank = "...",
	smallworld_mmr_change = "...",
	vanilla_mmr = "...",
	vanilla_rank = "...",
	vanilla_mmr_change = "...",
	is_connected = false,
}

local MMR_FIELDS = { "ranked_mmr", "smallworld_mmr", "vanilla_mmr" }
local MMR_CONFIGS = {
	{ "k_ranked", "ranked_mmr", "ranked_rank", "ranked_mmr_change" },
	{ "k_smallworld", "smallworld_mmr", "smallworld_rank", "smallworld_mmr_change" },
	{ "k_vanilla", "vanilla_mmr", "vanilla_rank", "vanilla_mmr_change" },
}

local function create_text_node(config)
	return { n = G.UIT.T, config = config }
end
local function create_row_node(config, nodes)
	return { n = G.UIT.R, config = config, nodes = nodes }
end
local function create_col_node(config, nodes)
	return { n = G.UIT.C, config = config, nodes = nodes }
end

local function create_ref_text_node(ref_value, scale, colour)
	return create_text_node({
		ref_table = MP.BMP_PROFILE_REF,
		ref_value = ref_value,
		scale = scale,
		colour = colour or G.C.UI.TEXT_LIGHT,
		shadow = true,
	})
end

local function update_profile_ref()
	local profile_data = MP.DISCORD_AUTH.get_profile_data()
	if not profile_data then return end

	if profile_data.username then MP.BMP_PROFILE_REF.username = profile_data.username end

	for _, field in ipairs(MMR_FIELDS) do
		if profile_data[field] ~= nil then MP.BMP_PROFILE_REF[field] = tostring(profile_data[field]) end
	end

	-- Update rank fields
	for _, config in ipairs(MMR_CONFIGS) do
		local rank_key = config[3]
		local mmr_change_key = config[4]

		if profile_data[rank_key] ~= nil then MP.BMP_PROFILE_REF[rank_key] = "#" .. tostring(profile_data[rank_key]) end

		if profile_data[mmr_change_key] ~= nil then
			local change = tonumber(profile_data[mmr_change_key])
			if change and change ~= 0 then
				local sign = change > 0 and "+" or "-"
				MP.BMP_PROFILE_REF[mmr_change_key] = sign .. tostring(math.floor(math.abs(change)))
			else
				MP.BMP_PROFILE_REF[mmr_change_key] = "—"
			end
		end
	end
end

local function get_mmr_change_colour(profile_data, mmr_change_key)
	if not profile_data or not profile_data[mmr_change_key] then return G.C.UI.TEXT_LIGHT end
	local change = tonumber(profile_data[mmr_change_key])
	if not change then return G.C.UI.TEXT_LIGHT end
	if change > 0 then
		return G.C.GREEN
	elseif change < 0 then
		return G.C.RED
	else
		return G.C.UI.TEXT_LIGHT
	end
end

local function create_gain_loss_col(queue_mmr_change_key)
	local profile_data = MP.DISCORD_AUTH.get_profile_data()
	local bg_colour = get_mmr_change_colour(profile_data, queue_mmr_change_key)

	return create_col_node({
		align = "cm",
		padding = 0.1,
		minw = 0.5,
		r = 0.1,
		colour = bg_colour,
		id = "bmp_mmr_change_" .. queue_mmr_change_key,
	}, {
		create_ref_text_node(queue_mmr_change_key, 0.35, G.C.WHITE),
	})
end

local function create_stat_row(ref_value, align, extra_stat_col_key)
	local nodes = { create_ref_text_node(ref_value, 0.6) }
	if extra_stat_col_key then table.insert(nodes, create_gain_loss_col(extra_stat_col_key)) end
	return create_row_node({
		align = align or "cm",
		padding = 0.15,
		minw = 1.45,
		r = 0.1,
		hover = true,
		colour = G.C.BLACK,
	}, nodes)
end

local function create_username_box()
	return create_col_node({ align = "cm", padding = 0.15, emboss = 0.1, r = 0.2, colour = G.C.L_BLACK, minw = 2.6 }, {
		create_ref_text_node("username", 0.6),
	})
end

local function create_queue_stats_box(queue_name_key, queue_mmr_key, queue_rank_key, queue_mmr_change_key)
	return create_col_node({ align = "cm", padding = 0.1, emboss = 0.1, r = 0.2, colour = G.C.L_BLACK, minw = 2.6 }, {
		create_row_node({ align = "cm" }, {
			create_text_node({
				text = localize(queue_name_key),
				scale = 0.35,
				colour = G.C.UI.TEXT_LIGHT,
				shadow = true,
			}),
		}),
		create_stat_row(queue_mmr_key, "tm", queue_mmr_change_key),
		create_stat_row(queue_rank_key, "cm"),
	})
end

local function create_button(button_config, sprite_atlas, sprite_pos)
	local base_config = {
		align = "cm",
		minw = 0.6,
		minh = 0.6,
		r = 0.1,
		hover = true,
		shadow = true,
		shadow_height = 0.5,
	}
	for k, v in pairs(button_config) do
		base_config[k] = v
	end
	return create_col_node(base_config, {
		{ n = G.UIT.O, config = { object = Sprite(0, 0, 0.3, 0.3, G.ASSET_ATLAS[sprite_atlas], sprite_pos) } },
	})
end

local function create_settings_button()
	return create_button({
		colour = G.C.GREY,
		button = "bmp_open_settings",
	}, "mod_tags", { x = 2, y = 0 })
end

local function create_discord_button()
	local is_connected = MP.DISCORD_AUTH.is_connected()
	return create_button({
		colour = is_connected and G.C.RED or HEX("5865F2"),
		button = is_connected and "disconnect_discord" or "connect_discord",
		on_demand_tooltip = {
			text = { localize(is_connected and "b_disconnect_discord" or "b_connect_discord") },
		},
	}, "icons", { x = 0, y = 0 })
end

local function create_user_row()
	return create_row_node({ align = "cl" }, {
		create_username_box(),
		create_col_node({ align = "cm", minw = 3 }, {
			create_row_node({ align = "cr", padding = 0.1 }, {
				create_settings_button(),
				create_discord_button(),
			}),
		}),
	})
end

local function create_profile_box(nodes)
	if MP.DISCORD_AUTH.is_connected() then
		for _, config in ipairs(MMR_CONFIGS) do
			table.insert(
				nodes,
				create_row_node({ align = "cl" }, {
					create_queue_stats_box(config[1], config[2], config[3], config[4]),
				})
			)
		end
	end

	return UIBox({
		definition = {
			n = G.UIT.ROOT,
			config = { align = "cm", colour = G.C.CLEAR },
			nodes = {
				create_col_node({
					align = "cm",
					padding = 0.1,
					r = 0.1,
					colour = G.C.CLEAR,
					outline_colour = G.C.BLACK,
					minw = 1,
					minh = 1,
				}, nodes),
			},
		},
		config = { align = "tli", bond = "Weak", offset = { x = -0.5, y = -0.5 }, major = G.ROOM_ATTACH },
	})
end

function G.FUNCS.bmp_open_settings(e)
	G.SETTINGS.paused = true
	if G.FUNCS["openModUI_Multiplayer"] then G.FUNCS["openModUI_Multiplayer"]({ config = { page = "config" } }) end
end

function MP.UI.Create_BMP_Profile()
	if MP.BMP_PROFILE_UI then
		MP.BMP_PROFILE_UI:remove()
		MP.BMP_PROFILE_UI = nil
	end
	if not G.MAIN_MENU_UI or G.OVERLAY_MENU then return end

	local is_connected = MP.DISCORD_AUTH.is_connected()
	MP.BMP_PROFILE_REF.is_connected = is_connected
	update_profile_ref()

	if not is_connected then MP.BMP_PROFILE_REF.username = MP.UTILS.get_username() or localize("k_profile_username") end

	local nodes = {}
	-- Always add user row
	table.insert(nodes, create_user_row())

	MP.BMP_PROFILE_UI = create_profile_box(nodes)
end

function MP.UI.Update_BMP_Profile()
	if not G.MAIN_MENU_UI or G.OVERLAY_MENU then return end
	if not MP.BMP_PROFILE_UI then
		MP.UI.Create_BMP_Profile()
		return
	end

	local is_connected = MP.DISCORD_AUTH.is_connected()
	local was_connected = MP.BMP_PROFILE_REF.is_connected
	local profile_data = MP.DISCORD_AUTH.get_profile_data()
	local had_profile_data = profile_data ~= nil

	MP.BMP_PROFILE_REF.is_connected = is_connected
	update_profile_ref()

	-- Recreate UI if connection state changed or profile data was just loaded
	if was_connected ~= is_connected or (not had_profile_data and profile_data) then
		MP.UI.Create_BMP_Profile()
	elseif profile_data then
		-- Update MMR change background colors
		for _, config in ipairs(MMR_CONFIGS) do
			local mmr_change_key = config[4]
			local color_node = MP.BMP_PROFILE_UI:get_UIE_by_ID("bmp_mmr_change_" .. mmr_change_key)
			if color_node and color_node.config then
				local new_colour = get_mmr_change_colour(profile_data, mmr_change_key)
				if color_node.config.colour ~= new_colour then color_node.config.colour = new_colour end
			end
		end
		MP.BMP_PROFILE_UI:recalculate()
	end
end
