Example one
====
将信息存放在文件中，以便重启使用

Table of Contents
=================

* [Example one](#Example one)
* [Nginx Conf](#Nginx Conf)
* [Lua Script](#Lua Script)
* [Installation](#installation)
* [Author](#author)
* [Copyright and License](#copyright-and-license)
* [See Also](#see-also)


Nginx Conf
========

```nginx
user  root;
worker_processes  1;
pid        logs/ngx_dy_upst_file.pid;
events {
    worker_connections  1024;
}

http {
    include       mime.types;
    default_type  application/octet-stream;
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    sendfile        on;
    keepalive_timeout  65;
    lua_shared_dict upstreams 1m;

    upstream default_upstream {
        server 127.0.0.1:8081;
        server 127.0.0.1:8082;
    }

    upstream lua_upstream {
        server 127.0.0.1:8084;
        server 127.0.0.1:8083;
    }

    init_by_lua_block {
            local dy_chose_upst = require "dy_chose_upst_file"
            dy_chose_upst.init_upstream()
    }

    server {
        listen       80;
        server_name  localhost;

        access_log  logs/80.access.log  main;
        error_log   logs/80.error.log error;

        location = /_switch_upstream {
            content_by_lua_block {
                    local dy_chose_upst = require "dy_chose_upst_file"
                    dy_chose_upst.choose_upstream()
            }
        }

        location / {
            set_by_lua_block $my_upstream {
                ngx.log(ngx.ERR, "http_host: ", ngx.var.http_host)
                local ups = ngx.shared.upstreams:get("selected_upstream")
                if ups ~= nil then
                    ngx.log(ngx.ERR, "get [", ups,"] from ngx.shared")
                    return ups
                end
                return "default_upstream"
            }

            #proxy_next_upstream off;
            proxy_set_header    X-Real-IP           $remote_addr;
            proxy_set_header    X-Forwarded-For     $proxy_add_x_forwarded_for;
            proxy_set_header    Host                $host;
            proxy_http_version  1.1;
            proxy_set_header    Connection  "";
            proxy_pass          http://$my_upstream ;
        }
    }   

    server {
        listen       8081;
        server_name  localhost;

        location / {
            root   html81;
            index  index.html index.htm;
        }
    }

    server {
        listen       8082;
        server_name  localhost;

        location / {
            root   html82;
            index  index.html index.htm;
        }
    }

    server {
        listen       8083;
        server_name  localhost;

        location / {
            root   html83;
            index  index.html index.htm;
        }
    }

    server {
        listen       8084;
        server_name  localhost;

        location / {
            root   html84;
            index  index.html index.htm;
        }
    }
}
```

Lua Script
========

```nginx
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
```

Installation
============
Copy the nginx conf and lua script to a location which is in the seaching path of lua require module 

[Back to TOC](#table-of-contents)

Author
======

xiaoxuanzi xiaoximou@gmail.com

[Back to TOC](#table-of-contents)

Copyright and License
=====================
The MIT License (MIT)
Copyright (c) 2018 xiaoxuanzi xiaoximou@gmail.com

[Back to TOC](#table-of-contents)

See Also
========
* Openresty-Lua动态修改upstream后端服务: https://github.com/Tinywan/lua-nginx-redis/blob/master/Nginx/Nginx-Web/openresty-nginx-lua-Proxy.md

[Back to TOC](#table-of-contents)

