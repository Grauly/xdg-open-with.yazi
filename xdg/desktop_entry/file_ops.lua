local retrieve_data_dirs = function()
    return os.getenv("XDG_DATA_DIRS"):split(":")
end

local url_to_desktop_id = function(strip_prefix, url)
    local url_string = tostring(url:strip_prefix(strip_prefix))
    url_string = url_string:gsub("-", "_")
    url_string = url_string:gsub("/", "-")
    return url_string
end


local collect_desktop_entries
collect_desktop_entries = function(applications_url, search_url)
    --should be using glob = "*.desktop", but it just does not work
    local files = get_files(search_url, {})
    local applications = {}
    for _, file in ipairs(files) do
        if (file.cha.is_dir) then
            local sub_applications = collect_desktop_entries(Url(search_url):join(file.name))
            applications = mergeTables(applications, sub_applications, false)
        else
            --hence, this workaround
            if file.name:endswith(".desktop") then
                applications[url_to_desktop_id(applications_url, file.url)] = file.url
            end
        end
    end
    return applications
end

local find_desktop_entries = function(dir)
    local search_location = Url(dir):join("applications")
    return collect_desktop_entries(search_location, search_location)
end

function find_all_desktop_entries()
    local data_dirs = retrieve_data_dirs()
    local desktop_entries = {}
    for _, v in ipairs(data_dirs) do
        local entries = find_desktop_entries(v)
        desktop_entries = mergeTables(desktop_entries, entries, false)
    end
    return desktop_entries
end