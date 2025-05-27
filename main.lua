Plugin_Name = "xdg-open-with"
Log_Prefix = "[" .. Plugin_Name .. "] "

local import = function(file)
    local home = os.getenv("HOME")
    local cfg_path = (os.getenv("YAZI_CONFIG_PATH") or ".config/yazi/plugins")
    local path = home .. "/" .. cfg_path .. "/" .. Plugin_Name .. ".yazi/" .. file
    local success, value = pcall(dofile, path)
    if not success then
        dbgerr(value)
    end
end

import("utils/ya.lua")
import("utils/table.lua")
import("utils/string.lua")
import("utils/list.lua")
import("utils/files.lua")

--needs a plugin named "nix-commands" with a database of commands
local get_nix_command = function(command)
    if (command:beginswith("/")) then return command end

    local loaded, content = pcall(require, "nix-commands")
    if not loaded then
        err(content)
        return command
    end
    if not content.commands then
        err("nix-commands does not have a commands section, defaulting")
        return command
    end
    local nix_command = content.commands[command]
    if not nix_command then
        err("nix-commands does not have a \"" .. command .. "\" defined")
        return command
    end
    return nix_command
end

--end of utils section

import("xdg/desktop_entry/file_ops.lua")
import("xdg/desktop_entry/parsing.lua")
import("xdg/desktop_entry/reading.lua")
import("xdg/desktop_entry/executing.lua")

local is_valid_entry = function(entry)
    local data = entry["data"]
    if data["Type"] ~= "Application" then return false, entry end
    if data["Name"] == nil then return false, entry end
    return true
end

local should_show_entry = function(entry)
    local valid = is_valid_entry(entry)
    if not valid then return false end
    if entry["NoDisplay"] then return false end
    if entry["Hidden"] then return false end
    if entry["OnlyShowIn"] ~= nil then
        local current_desktop = os.getenv("XDG_CURRENT_DESKTOP")
        local only_shows = entry["OnlyShowIn"]:split(";")
        local should_show = false
        for _, v in ipairs(only_shows) do
            if v == current_desktop then
                should_show = true
                break
            end
        end
        if not should_show then
            return false
        end
    end
    if entry["NotShowIn"] ~= nil then
        local current_desktop = os.getenv("XDG_CURRENT_DESKTOP")
        local dont_shows = entry["NotShowIn"]:split(";")
        local should_show = true
        for _, v in ipairs(dont_shows) do
            if v == current_desktop then
                should_show = false
                break
            end
        end
        if not should_show then
            return false
        end
    end
    --TODO: look for Path and Terminal Keys for launch command
end

local write_display_data = ya.sync(function(self, data)
    self.display_data = data
    ya.mgr_emit("plugin", { Plugin_Name, "refresh" })
    ya.render()
end)

local update_display_data = function(entries, files)
    --TODO: find mime types of files
    --TODO: find matching entries
    --TODO: make table like this per file:
    -- return a table of structure:
    -- {
    --  entries = { table of id -> actual entry }
    --  files =  {
    --      {
    --          file = { url and name }
    --          entries = { sorted list of entry ID's}
    --      }
    --  }
    -- }
    local display_files = {}
    for index, file in ipairs(files) do
        local applicable_entries = {}
        for id, entry in pairs(entries) do
            --TODO: actual mime type checks
            table.insert(applicable_entries, id)
        end
        table.insert(display_files, {
            file = file,
            entries = applicable_entries
        })
    end
    write_display_data({
        entries = entries,
        files = display_files
    })
end

--cursor ops
local change_tab = ya.sync(function(self, offset)
    local tab_count = (#self.display_data.files or 0)
    if tab_count == 0 then
        self.current_tab = 0
        self.cursor = {}
        return
    else
        if self.current_tab == 0 then
            self.current_tab = 1
        end
    end
    local new_tab = self.current_tab + offset
    if new_tab > tab_count then return end
    if new_tab < 1 then return end
    self.current_tab = new_tab
end)

local get_cursor_on_tab = ya.sync(function(self)
    change_tab(0)
    return self.cursor[self.current_tab] or 0
end)

local update_cursor_on_tab = ya.sync(function(self, offset)
    local new_cursor = get_cursor_on_tab() + offset
    local max_pos = (#(self.display_data.files[self.current_tab].entries or {}))
    if (new_cursor < 0) then
        self.cursor[self.current_tab] = 0
    elseif (new_cursor > max_pos) then
        self.cursor[self.current_tab] = max_pos
    else
        self.cursor[self.current_tab] = new_cursor
    end
end)

-- main refresh op

local refresh = function()
    change_tab(0)
    update_cursor_on_tab(0)
end

--ui open/close
local open_ui_if_not_open = ya.sync(function(self)
    if not self.children then
        self.children = Modal:children_add(self, 10)
    end
    ya.render()
end)

local close_ui_if_open = ya.sync(function(self)
    if self.children then
        Modal:children_remove(self.children)
        self.children = nil
    end
    ya.render()
end)

--shamelessly stolen from https://github.com/yazi-rs/plugins/tree/main/chmod.yazi
local selected_or_hovered = ya.sync(function()
    local tab, paths = cx.active, {}
    for _, u in pairs(tab.selected) do
        paths[#paths + 1] = tostring(u)
    end
    if #paths == 0 and tab.current.hovered then
        paths[1] = tostring(tab.current.hovered.url)
    end
    return paths
end)

--requires aync context to run

local sc = function(on, run)
    return { on = on, run = run }
end


local M = {
    keys = {
        sc("q", "quit"),
        sc("<Escape>", "quit"),
        sc("<Up>", "up"),
        sc("<Down>", "down"),
        sc("<Enter>", "open"),
        sc("<S-Enter>", "open-in-terminal"),
        sc("<Left>", "prev-file"),
        sc("<Right>", "next-file"),
    },
    current_tab = 0,
    cursor = {},
    display_data = {
        entries = {},
        files = {}
    },
    draw_area = {
        full = {},
        header = {},
        list = {}
    }
}

--entry point, async
function M:entry(job)
    if (job.args[1] == "refresh") then
        refresh()
        return
    end
    open_ui_if_not_open()
    local files = selected_or_hovered()
    local entries = find_all_desktop_entries()
    local parsed_entries = {}
    for k, v in pairs(entries) do
        parsed_entries[k] = read_desktop_entry(k, tostring(v))
    end
    update_display_data(parsed_entries, files)
    self.user_input(self)
end

function M:user_input()
    while true do
        local action = (self.keys[ya.which { cands = self.keys, silent = true }] or { run = "invalid" }).run
        if action == "quit" then
            close_ui_if_open()
            return
        end
        self.act_user_input(self, action)
    end
end

function M:act_user_input(action)
    if action == "up" then
        update_cursor_on_tab(-1)
    elseif action == "down" then
        update_cursor_on_tab(1)
    elseif action == "prev-file" then
        change_tab(-1)
    elseif action == "next-file" then
        change_tab(1)
    end
end

-- Modal functions
function M:new(area)
    self:layout(area)
    return self
end

-- Not a modal function but a helper to get the layout
function M:layout(area)
    local h_chunks = ui.Layout()
        :direction(ui.Layout.HORIZONTAL)
        :constraints({
            ui.Constraint.Percentage(25),
            ui.Constraint.Percentage(50),
            ui.Constraint.Percentage(25)
        })
        :split(area)
    local v_chunks = ui.Layout()
        :direction(ui.Layout.VERTICAL)
        :constraints({
            ui.Constraint.Percentage(10),
            ui.Constraint.Percentage(80),
            ui.Constraint.Percentage(10)
        })
        :split(h_chunks[2])
    local areas = ui.Layout()
        :direction(ui.Layout.VERTICAL)
        :constraints({
            ui.Constraint.Length(3),
            ui.Constraint.Fill(1)
        })
        :split(v_chunks[2])

    self.draw_area = {
        full = v_chunks[2],
        header = areas[1],
        list = areas[2]
    }
end

function M:reflow()
    return { self }
end

-- actually draw the content, is synced, so cannot use Command
function M:redraw()
    local data = self.display_data.files[self.current_tab] or { file = {}, entries = {} }
    local rows = {}
    local file_name = (Url(tostring(data.file))).name or "Error"
    for i, v in ipairs(data.entries) do
        local entry = (self.display_data.entries[v] or {}).data
        rows[i] = ui.Row { "", (entry["Name"]["base"] or "undefined"), "" }
    end
    -- basically stolen from https://github.com/yazi-rs/plugins/blob/a1738e8088366ba73b33da5f45010796fb33221e/mount.yazi/main.lua#L144
    return {
        ui.Clear(self.draw_area.full),
        ui.Border(ui.Border.ALL)
            :area(self.draw_area.full)
            :type(ui.Border.ROUNDED)
            :style(ui.Style():fg("blue"))
            :title(ui.Line("Open with: " .. tostring(self.current_tab) .. "/" .. tostring((#self.display_data.files or 0))):align(ui.Line.LEFT)),
        ui.Text(file_name)
            :align(ui.Text.LEFT)
            :area(self.draw_area.header:pad(ui.Pad(1, 2, 0, 2))),
        ui.Border(ui.Border.BOTTOM)
            :area(self.draw_area.header:pad(ui.Pad.x(1)))
            :type(ui.Border.PLAIN)
            :style(ui.Style():fg("blue")),
        ui.Text("Program")
            :align(ui.Text.LEFT)
            :area(self.draw_area.list:pad(ui.Pad.x(1)))
            :style(ui.Style():bold()),
        ui.Table(rows)
            :area(self.draw_area.list:pad(ui.Pad(1, 2, 1, 2)))
            :row(get_cursor_on_tab())
            :row_style(ui.Style():fg("blue"):reverse())
            :widths {
                ui.Constraint.Percentage(5),
                ui.Constraint.Percentage(85),
                ui.Constraint.Percentage(10),
            },
    }
end

return M
