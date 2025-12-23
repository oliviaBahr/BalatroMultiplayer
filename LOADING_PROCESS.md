# Game Loading Process

This document describes the game loading sequence and how Discord profile loading fits into it.

## Overview

The game loading process follows a specific sequence: game engine initialization → mod loading → item injection → main menu. Discord profile loading happens **after** the main menu is opened, not during initial game startup.

## Detailed Loading Sequence

### 1. Game Engine Initialization (`main.lua`)

The game starts with `love.run()` which calls `love.load()`:

```86:118:balatro-source-code/main.lua
function love.load() 
	G:start_up()
	--Steam integration
	local os = love.system.getOS()
	if os == 'OS X' or os == 'Windows' then 
		local st = nil
		--To control when steam communication happens, make sure to send updates to steam as little as possible
		if os == 'OS X' then
			local dir = love.filesystem.getSourceBaseDirectory()
			local old_cpath = package.cpath
			package.cpath = package.cpath .. ';' .. dir .. '/?.so'
			st = require 'luasteam'
			package.cpath = old_cpath
		else
			st = require 'luasteam'
		end

		st.send_control = {
			last_sent_time = -200,
			last_sent_stage = -1,
			force = false,
		}
		if not (st.init and st:init()) then
			love.event.quit()
		end
		--Set up the render window and the stage for the splash screen, then enter the gameloop with :update
		G.STEAM = st
	else
	end

	--Set the mouse to invisible immediately, this visibility is handled in the G.CONTROLLER
	love.mouse.setVisible(false)
end
```

### 2. Game Startup (`game.lua` - `Game:start_up()`)

The `start_up()` method initializes core game systems:

- **Settings loading**: Loads and processes game settings
- **Window initialization**: Sets up the game window
- **Sound Manager**: Initializes sound thread (if enabled)
- **Save Manager**: Starts save manager thread
- **HTTP Manager**: Starts HTTP manager thread for score submissions
- **Shaders**: Loads all shader files
- **Controllers**: Initializes input handling
- **Profile loading**: Loads player profile
- **Localization**: Sets up language
- **Item prototypes**: Initializes game objects (cards, jokers, etc.)

During this phase, `initSteamodded()` is called which loads all mods.

### 3. Mod Loading (Steamodded Loader)

The mod loading process happens in `smods-1.0.0-beta-1016c/src/loader.lua`:

1. **Load APIs**: Loads modding APIs
2. **Load Mods**: Iterates through all mods and loads them synchronously:
   - Each mod's `main_file` (typically `core.lua`) is executed
   - Mods are loaded in priority order
   - Config files are loaded before mod code execution
3. **Inject Items**: After all mods are loaded, `SMODS.injectItems()` is called to inject modded content into the game

### 4. BalatroMultiplayer Mod Loading (`core.lua`)

The Multiplayer mod's `core.lua` is executed during mod loading. It:

1. **Initializes mod state**: Sets up `MP` namespace and default values
2. **Loads utility modules**: 
   - `misc/utils.lua`
   - `misc/insane_int.lua`
   - `misc/hide_content.lua`
   - `misc/http_client.lua`
   - **`misc/discord_auth.lua`** ← Discord auth module loaded here
   - `misc/debug_borders.lua`
3. **Loads compatibility modules**: All files in `compatibility/`
4. **Loads networking**: Action handlers and socket code
5. **Loads UI components**: Required for gamemodes and rulesets
6. **Loads game objects**: Rulesets, gamemodes, jokers, decks, etc.
7. **Loads UI**: All UI components
8. **Starts networking thread**: Creates and starts the networking thread

**Important**: At this point, the Discord auth module is loaded but **no profile fetching occurs**. The module is just initialized with empty state.

### 5. Item Injection

After all mods are loaded, `SMODS.injectItems()` is called to:
- Inject modded objects into game prototypes
- Initialize localization
- Process unlocks and discoveries

### 6. Game Continues

After mod loading completes, the game continues with:
- Splash screen display
- Main menu initialization

## Discord Profile Loading

### When It Happens

Discord profile loading does **NOT** happen during initial game/mod loading. Instead, it happens when:

1. **Main menu is opened**: When `set_main_menu_UI()` is called in `ui/main_menu.lua`:

```178:182:BalatroMultiplayer/ui/main_menu.lua
	-- Add BMP profile UI in upper left corner
	if MP.UI.Create_BMP_Profile then MP.UI.Create_BMP_Profile() end

	-- Refresh profile data if connected (refresh on main menu open)
	if MP.DISCORD_AUTH and MP.DISCORD_AUTH.is_connected() then MP.DISCORD_AUTH.fetch_profile() end
```

2. **After successful Discord authentication**: When `MP.DISCORD_AUTH.handle_callback()` is called after user completes OAuth flow:

```141:142:BalatroMultiplayer/misc/discord_auth.lua
	-- Fetch profile data after successful connection
	MP.DISCORD_AUTH.fetch_profile()
```

### How It Works

The `fetch_profile()` function in `misc/discord_auth.lua`:

1. **Checks connection**: Verifies user is authenticated (has token and user_id)
2. **Sets loading state**: Marks profile as loading to prevent duplicate requests
3. **Starts profile thread**: Creates a separate thread (`discord_profile_thread.lua`) to fetch profile data
4. **Thread makes HTTP requests**: The thread makes HTTP requests **asynchronously** (non-blocking):
   - 1 request for Discord user info (username, avatar)
   - 6 requests for MMR data (3 queues × 2 requests each: rank data + last game data)
5. **Thread sends data**: When complete, the thread sends profile data via a channel
6. **Main thread receives data**: The `update()` function checks for profile data and updates `MP.DISCORD_AUTH.profile_data`
7. **Updates UI**: Triggers UI refresh when complete

### Non-Blocking Behavior

**NO, Discord profile loading does NOT block the game thread.**

Profile fetching now runs in a separate thread (`discord_profile_thread.lua`):

- When `fetch_profile()` is called, it immediately starts a thread and returns (non-blocking)
- The thread makes all 7 HTTP requests independently
- The main game thread continues running normally
- Profile data is received asynchronously via a channel when ready
- The `update()` function checks for profile data each frame (non-blocking check)

### Profile Loading Flow

```
Main Menu Opens
    ↓
Check if Discord connected
    ↓ (if connected)
Call fetch_profile()
    ↓
Start profile thread (non-blocking, returns immediately)
    ↓
Game continues running normally
    ↓
[In separate thread]
    ↓
Fetch Discord user info (1 request)
    ↓
Fetch ranked MMR data (1 request)
    ↓
Fetch ranked last game (1 request)
    ↓
Fetch smallworld MMR data (1 request)
    ↓
Fetch smallworld last game (1 request)
    ↓
Fetch vanilla MMR data (1 request)
    ↓
Fetch vanilla last game (1 request)
    ↓
Send profile data via channel
    ↓
[Back in main thread]
    ↓
update() checks channel (non-blocking)
    ↓
Receive profile data
    ↓
Update profile_data
    ↓
Update UI
```

### Update Loop Integration

The Discord auth module has an update function that checks for OAuth callbacks and profile data:

```314:318:BalatroMultiplayer/misc/discord_auth.lua
-- Update function to check for callbacks and profile data (call this in game update loop)
-- This checks channels for messages from both the auth thread and profile thread
function MP.DISCORD_AUTH.update(dt)
	check_callback()
	check_profile_data()
end
```

This is called from the networking action handlers update loop:

```1031:1031:BalatroMultiplayer/networking/action_handlers.lua
	if MP.DISCORD_AUTH and MP.DISCORD_AUTH.update then MP.DISCORD_AUTH.update(dt) end
```

This update function is **non-blocking** - it only checks channels for messages and doesn't make HTTP requests. All HTTP requests happen in separate threads.

## Summary

- **Initial game load**: Discord profile is **NOT** fetched during startup
- **Main menu open**: Profile is fetched if user is connected (NON-BLOCKING)
- **After OAuth**: Profile is fetched after successful authentication (NON-BLOCKING)
- **Non-blocking**: All HTTP requests run in a separate thread and do not block the game thread
- **Update loop**: Checks for OAuth callbacks and profile data (non-blocking)

Profile fetching is now fully asynchronous. When `fetch_profile()` is called, it starts a background thread that handles all HTTP requests. The game continues running normally, and profile data is received via a channel when ready. This eliminates any freezing or blocking when opening the main menu or after authentication.

