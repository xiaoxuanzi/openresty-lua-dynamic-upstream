local io = io
local os = os
local json = require "cjson"
local cjson_safe = require "cjson.safe"
--local libluafs = require "libluafs"

local conf = {
    fname = "select_upstream.json",
    upstream_list = {"lua_upstream", "default_upstream"}
}

local  _M = {}

local function write( fpath, data, mode )
    local fp
    local rst
    local err_msg

    fp, err_msg = io.open( fpath, mode or 'w' )
    if fp == nil then
        return nil, 'FileError', err_msg
    end

    rst, err_msg = fp:write( data )
    if rst == nil then
        fp:close()
        return nil, 'FileError', err_msg
    end

    fp:close()

    return #data, nil, nil
end

local function read( fpath, mode )
    local fp
    local data
    local err_msg

    fp, err_msg = io.open( fpath , mode or 'r' )
    if fp == nil then
        return nil, 'FileError', err_msg
    end

    data = fp:read( '*a' )
    fp:close()

    if data == nil then
        return nil, 'FileError',
            'read data error,file path:' .. fpath
    end

    return data, nil, nil
end

local function is_file(path)
    return libluafs.is_file(path)
end

local function table_has_element(table, element)
    for _, v in ipairs(table) do
        if v == element then
            return true
        end
    end

    return false
end

function _M.init_upstream()
    --[[
    if not is_file(conf.fname) then
        ngx.log(ngx.INFO, "No file found")
        return
    end
    --]]

    local raw, err, err_msg = read(conf.fname)
    if err ~= nil then
        ngx.log(ngx.ERR, "[ERROR] ", err_msg)
        error("[ERROR] ".. err_msg)
    end

    local selected_upstream, err = cjson_safe.decode(raw)
    if err ~= nil then
        ngx.log(ngx.ERR, "[ERROR] JSON encode failed! error: ", err)
        error("[ERROR] JSON encode failed! err: ", err)
    end

    local upstreams = ngx.shared.upstreams
    local succ, err, forcible = upstreams:set("selected_upstream", selected_upstream["upstream_name"])
    if not succ then
        error("ngx.shared.DICT init failed! error :", err)
    end

    ngx.log(ngx.INFO, "ngx.shared.DICT init success!")
end

local function _choose_upstream()

    local ups = ngx.req.get_uri_args()["upstream"]
    if ups == nil or ups == "" then
        ngx.say("upstream is nil 1")
        return
    end


    if table_has_element(conf.upstream_list, ups) == false then
        ngx.say(ups .. "isn't in upstream list")
        return
    end

    local select_upstream = {
        upstream_name = ups,
        time = os.date()
    }

    local upstream_msg, err = cjson_safe.encode(select_upstream)
    if err ~= nil then
        ngx.say("[ERROR] JSON encode failed! err: ", err)
        ngx.log(ngx.ERR, "[ERROR] JSON encode failed! error: ", err)
        return
    end

    local _, err, err_msg = write(conf.fname, upstream_msg)
    if err ~= nil then
        ngx.say("[ERROR] ".. err_msg)
        ngx.log(ngx.ERR, "[ERROR] ".. err_msg)
        return
    end

    local upstreams = ngx.shared.upstreams
    local succ, err, forcible = upstreams:set("selected_upstream",  ups)

    if not succ then
        ngx.say("ngx.shared.DICT stored failed! error :", err)
        return
    end

    ngx.say("Current upstream is :", ups)

end

local function errorlog(err)
    return string.format("%s: %s", err or "", debug.traceback())
end

function _M.choose_upstream()
    local status, err = xpcall(_choose_upstream, errorlog)
        if not status then
        ngx.log(ngx.ERR, "[ERROR] choose_upstream failed! error: ", err)
    end
end

return _M
