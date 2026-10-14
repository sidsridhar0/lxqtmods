if hl.plugin.dynamic_cursors then
  hl.config { plugin = { dynamic_cursors = {
    enabled   = true,
    mode      = "none",     -- keep the pointer upright
    threshold = 2,        -- min angle change (°) before redraw; lower = smoother

    rotate = {
      length = 20,        -- stick length in px, ≈ your cursor size
      offset = 0.0,       -- clockwise angle offset for ALL shapes
    },

    tilt = {
      limit      = 5000,  -- speed (px/s) for full tilt; lower = tiltier
      activation = "negative_quadratic", -- "linear" | "quadratic" | "negative_quadratic"
      window     = 100,   -- ms of speed averaging; higher = smoother but laggier
      full       = 60,    -- max tilt each side (°)
    },

    stretch = {
      limit      = 3000,  -- speed (px/s) for full 2x stretch
      activation = "quadratic",
      window     = 100,
    },

    shake = {
      enabled   = true,
      threshold = 6.0,    -- lower = shake detected sooner
      base      = 4.0,    -- instant zoom on shake
      speed     = 4.0,    -- extra zoom per second of shaking
      influence = 0.0,    -- how much shake intensity affects speed
      limit     = 0.0,    -- max zoom (<1 = no limit)
      timeout   = 2000,   -- ms to stay big after shaking stops
      effects   = false,  -- keep tilt/rotate active while big
      ipc       = false,  -- emit shakestart/update/end on socket2
    },

    hyprcursor = {
      enabled    = true,
      nearest    = 1,     -- 0 never pixelated, 1 when no hi-res, 2 always
      resolution = -1,    -- -1 = cursor size × shake.base
      fallback   = "clientside",
    },
  }}}

  -- optional per-shape overrides (server-side cursors only)
  hl.plugin.dynamic_cursors.shape_rule { shape = "text", mode = "none" }
  hl.plugin.dynamic_cursors.shape_rule { shape = "grab", mode = "stretch", stretch = { limit = 2000 } }
end

if hl.plugin.hyprbars then
  hl.config({
    plugin = {
      hyprbars = {
        enabled = true,
        bar_height = 34,
        bar_color = "rgb(292b33)",
        col = { text = "rgb(f2f2f5)" },
        bar_text_size = 12,
        bar_text_weight = "medium",
        bar_text_font = "Google Sans",
        bar_text_align = "left",
        bar_part_of_window = true,
        bar_padding = 12,
        bar_button_padding = 6,
      },
    },
  })

  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(e35b69)",
    fg_color = "rgb(ffffff)",
    size = 18,
    icon = "×",
    action = [[hyprctl dispatch 'hl.dsp.window.close()']],
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(6578c8)",
    fg_color = "rgb(ffffff)",
    size = 18,
    icon = "□",
    action = [[hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })']],
  })
  hl.plugin.hyprbars.add_button({
    bg_color = "rgb(646b78)",
    fg_color = "rgb(ffffff)",
    size = 18,
    icon = "−",
    action = [[hyprctl eval 'LucidSpecials.minimize()']],
  })
end