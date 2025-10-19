-- Ultra-Optimized Body Yaw Resolver - Maximum FPS Performance
-- No ESP modifications, pure resolver with on-screen info only

-- Ultra-aggressive function caching
local entity_get_prop = entity.get_prop
local entity_get_origin = entity.get_origin
local entity_is_alive = entity.is_alive
local entity_is_dormant = entity.is_dormant
local entity_get_players = entity.get_players
local entity_get_local_player = entity.get_local_player
local entity_get_player_name = entity.get_player_name
local globals_tickcount = globals.tickcount
local globals_tickinterval = globals.tickinterval
local globals_realtime = globals.realtime
local renderer_text = renderer.text
local plist_set = plist.set
local math_abs = math.abs
local math_sqrt = math.sqrt
local math_deg = math.deg
local math_atan2 = math.atan2
local math_min = math.min
local math_max = math.max
local client_camera_angles = client.camera_angles

-- Configuration
local cfg = {
    enabled = ui.new_checkbox("RAGE", "Other", "Enable Body Yaw Resolver"),
}

-- Minimal data storage
local targets = {}
local active_target = nil
local last_target_update = 0
local last_resolve_tick = 0

-- Ultra-minimal constants
local CONST = {
    TARGET_UPDATE_INTERVAL = 0.15,  -- Update target selection every 150ms
    RESOLVE_EVERY_N_TICKS = 2,      -- Resolve every 2 ticks to save CPU
    MAX_TARGET_DIST = 3000,
    JITTER_THRESHOLD = 28,
    BODY_THRESHOLD = 30,
    DEF_SIMTIME_MULT = 1.7,
    HISTORY_SIZE = 8,               -- Reduced from 16
}

-- Fast angle math
local function norm(a)
    a = a % 360
    return a > 180 and a - 360 or (a < -180 and a + 360 or a)
end

local function delta(a, b)
    return math_abs(norm(a - b))
end

-- Get angle to position
local function get_angle(fx, fy, tx, ty)
    return math_deg(math_atan2(ty - fy, tx - fx))
end

-- Get 2D distance
local function get_dist(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    return math_sqrt(dx * dx + dy * dy)
end

-- Initialize target data (minimal)
local function init_target(ent)
    if not targets[ent] then
        targets[ent] = {
            a = {0,0,0,0,0,0,0,0},  -- angles
            i = 0,                  -- index
            c = 0,                  -- count
            by = 0,                 -- body yaw
            bd = 0,                 -- body delta
            ey = 0,                 -- eye yaw
            st = 0,                 -- simtime
            lst = 0,                -- last simtime
            jt = false,             -- jitter active
            js = 0,                 -- jitter side
            df = false,             -- defensive
            dt = 0,                 -- defensive tick
            res = 0,                -- resolved angle
            conf = 0,               -- confidence
            meth = "NONE",          -- method
            h = 0,                  -- hits
            m = 0,                  -- misses
            bi = 0,                 -- brute index
        }
    end
    return targets[ent]
end

-- Select best target (optimized)
local function get_best_target(me)
    local now = globals_realtime()
    
    -- Cache target selection
    if active_target and entity_is_alive(active_target) and not entity_is_dormant(active_target) then
        if now - last_target_update < CONST.TARGET_UPDATE_INTERVAL then
            return active_target
        end
    end
    
    last_target_update = now
    
    local mx, my = entity_get_origin(me)
    if not mx then return nil end
    
    local _, yaw = client_camera_angles()
    if not yaw then return nil end
    
    local players = entity_get_players(true)
    local best, best_score = nil, 9999
    
    for i = 1, #players do
        local p = players[i]
        if entity_is_alive(p) and not entity_is_dormant(p) then
            local px, py = entity_get_origin(p)
            if px then
                local dist = get_dist(mx, my, px, py)
                if dist < CONST.MAX_TARGET_DIST then
                    local ang = get_angle(mx, my, px, py)
                    local fov = delta(yaw, ang)
                    local score = fov * 0.7 + (dist / CONST.MAX_TARGET_DIST) * 100 * 0.3
                    
                    if score < best_score then
                        best_score = score
                        best = p
                    end
                end
            end
        end
    end
    
    active_target = best
    return best
end

-- Detect jitter (ultra-fast)
local function check_jitter(t)
    if t.c < 4 then return false end
    
    local flips, side = 0, 0
    for i = 0, 3 do
        local i1 = (t.i - i - 1) % CONST.HISTORY_SIZE + 1
        local i2 = (t.i - i - 2) % CONST.HISTORY_SIZE + 1
        local d = norm(t.a[i1] - t.a[i2])
        if math_abs(d) > CONST.JITTER_THRESHOLD then
            flips = flips + 1
            side = side + (d > 0 and 1 or -1)
        end
    end
    
    t.jt = flips >= 2
    t.js = side > 0 and 1 or -1
    return t.jt
end

-- Detect defensive (ultra-fast)
local function check_defensive(ent, t)
    local st = entity_get_prop(ent, "m_flSimulationTime")
    if not st then return false end
    
    t.lst = t.st
    t.st = st
    
    if t.lst > 0 then
        local d = st - t.lst
        local ti = globals_tickinterval()
        
        if d > ti * CONST.DEF_SIMTIME_MULT or d < -ti * 0.5 then
            t.df = true
            t.dt = globals_tickcount()
            return true
        end
        
        if t.df and (globals_tickcount() - t.dt) > 16 then
            t.df = false
        end
    end
    
    return t.df
end

-- Main resolver (ultra-optimized)
local function resolve(ent, t, me)
    -- Update angle
    local ey = entity_get_prop(ent, "m_angEyeAngles[1]")
    if not ey then return end
    
    t.ey = ey
    t.i = (t.i % CONST.HISTORY_SIZE) + 1
    t.a[t.i] = ey
    t.c = math_min(t.c + 1, CONST.HISTORY_SIZE)
    
    -- Get positions
    local mx, my = entity_get_origin(me)
    local px, py = entity_get_origin(ent)
    if not mx or not px then return end
    
    local ideal = get_angle(mx, my, px, py)
    
    -- Body yaw
    local by = entity_get_prop(ent, "m_flLowerBodyYawTarget")
    if by then
        t.by = by
        t.bd = norm(by - ideal)
    end
    
    -- Detections
    local jit = check_jitter(t)
    local def = check_defensive(ent, t)
    
    -- Resolve
    local ang, w = 0, 0
    local body_off = math_abs(t.bd) > CONST.BODY_THRESHOLD and (t.bd > 0 and 60 or -60) or 0
    
    -- Body layer
    local ba = ideal + body_off
    ang = ang + ba * 0.45
    w = w + 0.45
    t.meth = "BODY"
    
    -- Jitter layer
    if jit then
        local ja = ideal + (58 * t.js)
        ang = ang + ja * 0.35
        w = w + 0.35
        t.meth = "JITTER"
    end
    
    -- Defensive layer
    if def then
        local da = t.a[math_max(1, t.i - 2)]
        ang = ang + da * 0.15
        w = w + 0.15
        t.meth = "DEFENSIVE"
    end
    
    -- Brute layer
    local offsets = {60,-60,90,-90,45,-45,30,-30}
    local bo = ideal + offsets[(t.bi % 8) + 1]
    ang = ang + bo * 0.05
    w = w + 0.05
    
    -- Finalize
    t.res = w > 0 and norm(ang / w) or ideal
    t.conf = math_min(w, 1)
    
    -- Apply
    plist_set(ent, "Override yaw", t.res)
    plist_set(ent, "Force body yaw", true)
end

-- Draw info (minimal, optimized)
local function draw_info()
    if not ui.get(cfg.enabled) or not active_target then return end
    
    local t = targets[active_target]
    if not t then return end
    
    local y = 200
    local x = 10
    
    -- Header
    renderer_text(x, y, 120, 180, 255, 255, "b", 0, "RESOLVER")
    y = y + 18
    
    -- Target name
    local name = entity_get_player_name(active_target)
    renderer_text(x, y, 255, 255, 100, 255, nil, 0, name)
    y = y + 14
    
    -- Body yaw
    local br = math_abs(t.bd) > 35 and 255 or 150
    renderer_text(x, y, br, 200, 100, 255, nil, 0, string.format("Body: %.0f°", t.by))
    y = y + 14
    
    -- Eye yaw
    renderer_text(x, y, 180, 180, 255, 255, nil, 0, string.format("Eye: %.0f°", t.ey))
    y = y + 14
    
    -- Delta
    local dr = math_abs(t.bd) > 50 and 255 or 200
    renderer_text(x, y, dr, 150, 150, 255, nil, 0, string.format("Δ: %.0f°", t.bd))
    y = y + 16
    
    -- Status
    if t.jt then
        renderer_text(x, y, 255, 100, 100, 255, nil, 0, "JIT " .. (t.js > 0 and "R" or "L"))
        y = y + 14
    end
    
    if t.df then
        renderer_text(x, y, 200, 100, 255, 255, nil, 0, "DEFENSIVE")
        y = y + 14
    end
    
    -- Method
    local mr = t.meth == "BODY" and 100 or (t.meth == "JITTER" and 255 or 200)
    local mg = t.meth == "BODY" and 255 or 150
    renderer_text(x, y, mr, mg, 150, 255, "b", 0, t.meth)
    y = y + 14
    
    -- Confidence
    local cp = t.conf * 100
    local cr = cp > 70 and 100 or 255
    local cg = cp > 70 and 255 or 150
    renderer_text(x, y, cr, cg, 100, 255, nil, 0, string.format("%.0f%%", cp))
    y = y + 14
    
    -- Accuracy
    if t.h + t.m > 0 then
        local acc = (t.h / (t.h + t.m)) * 100
        local ar = acc > 50 and 100 or 255
        local ag = acc > 50 and 255 or 100
        renderer_text(x, y, ar, ag, 100, 255, nil, 0, string.format("%.0f%% (%d/%d)", acc, t.h, t.h + t.m))
    end
end

-- Indicator (minimal)
local function draw_indicator()
    if not ui.get(cfg.enabled) or not active_target then return end
    
    local t = targets[active_target]
    if not t or t.conf < 0.2 then return end
    
    local sw, sh = client.screen_size()
    local x = sw / 2 + 15
    local y = sh / 2 + 35
    
    -- Watermark
    renderer_text(x, y - 15, 120, 180, 255, 220, "-", 0, "RSLV")
    
    -- Method
    local r, g, b = 255, 255, 255
    local txt = "BDY"
    
    if t.jt then
        r, g, b = 255, 120, 120
        txt = "JIT"
    elseif t.df then
        r, g, b = 220, 120, 255
        txt = "DEF"
    elseif t.meth == "BODY" then
        r, g, b = 120, 255, 120
        txt = "BDY"
    end
    
    renderer.indicator(r, g, b, math_min(255, t.conf * 255), txt)
    
    -- Confidence
    local cp = t.conf * 100
    local cr = cp > 70 and 120 or 255
    local cg = cp > 70 and 255 or 150
    renderer_text(x, y, cr, cg, 100, 255, "-", 0, string.format("%.0f%%", cp))
end

-- Main loop (throttled)
local function on_predict()
    if not ui.get(cfg.enabled) then return end
    
    local tick = globals_tickcount()
    if tick - last_resolve_tick < CONST.RESOLVE_EVERY_N_TICKS then return end
    last_resolve_tick = tick
    
    local me = entity_get_local_player()
    if not me or not entity_is_alive(me) then return end
    
    local tgt = get_best_target(me)
    if not tgt then return end
    
    local t = init_target(tgt)
    resolve(tgt, t, me)
end

-- Paint (only draw, no logic)
local function on_paint()
    if not ui.get(cfg.enabled) then return end
    draw_info()
    draw_indicator()
end

-- Events
local function on_miss(e)
    local tgt = client.userid_to_entindex(e.target)
    if not tgt then return end
    local t = init_target(tgt)
    t.m = t.m + 1
    t.bi = t.bi + 1
end

local function on_hit(e)
    local tgt = client.userid_to_entindex(e.target)
    if not tgt then return end
    local t = init_target(tgt)
    t.h = t.h + 1
end

local function on_round()
    targets = {}
    active_target = nil
end

-- Register
client.set_event_callback("pre_prediction", on_predict)
client.set_event_callback("paint", on_paint)
client.set_event_callback("aim_miss", on_miss)
client.set_event_callback("aim_hit", on_hit)
client.set_event_callback("round_start", on_round)

client.color_log(100, 255, 100, "[Resolver] Ultra-Optimized | Minimal FPS Impact")